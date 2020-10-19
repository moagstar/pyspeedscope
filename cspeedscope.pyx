# cython: profile=True
""" Speedscope recorder for python.

See also: https://www.speedscope.app
"""
import inspect
import sys
import time

from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free


cdef struct Record:
    float timestamp
    char typ
    int frame_index


BUF_SIZE = 2 ** 16


class LazyList(list):

    def __init__(self, generator):
        self.generator = generator

    def __iter__(self):
        return self.generator

    def __len__(self):
        return 1


cdef class Recorder:

    cdef Record* _records
    cdef public int num_records
    cdef public int length
    cdef float _begin_time
    cdef float _end_time
    cdef dict frame_cache

    def __cinit__(self):
        self.frame_cache = {}
        self._records = <Record*> PyMem_Malloc(BUF_SIZE * sizeof(Record))
        self.num_records = 0
        self.length = BUF_SIZE

    def __dealloc__(self):
        PyMem_Free(self._records)

    def start(self, profile=True):
        self._begin_time = time.perf_counter()
        if profile:
            sys.setprofile(self._trace_func)

    def stop(self, profile=True):
        if profile:
            sys.setprofile(None)
        self._end_time = time.perf_counter()

    def _trace_func(self, frame, str event, arg):

        code = frame.f_code
        filename = code.co_filename

        if filename != __file__:
            if event == "call":
                typ = ord("O")
            elif event == "return":
                type = ord("C")

        self._maybe_resize()

        key = code.co_name, filename, code.co_firstlineno
        if key in self.frame_cache:
            frame_index = self.frame_cache[key][0]
        else:
            frame_index = len(self.frame_cache)
            self.frame_cache[key] = frame_index, key

        self._records[self.num_records] = Record(
            time.perf_counter(),
            typ,
            frame_index,
        )
        self.num_records += 1

    cdef _maybe_resize(self):
        if self.num_records == self.length:
            self.length *= 2
            mem = <Record*> PyMem_Realloc(self._records, self.length * sizeof(Record))
            if not mem:
                raise MemoryError()
            self._records = mem

    @property
    def events(self):
        return (
            {
                "type": chr(self._records[i].typ),
                "at": int(self._records[i].timestamp * 1e9),
                "frame": self._records[i].frame_index,
            }
            for i in range(self.num_records)
        )

    @property
    def frames(self):
        return (
            {
                "name": name,
                "file": filename,
                "line": line,
                "col": 1,
            }
            for index, (name, filename, line) in self.frame_cache.values()
        )

    def export_to_json(self, filename_or_stream):

        if isinstance(filename_or_stream, str):
            with open(filename_or_stream, 'w') as f:
                return self.export_to_json(f)

        try:
            import rapidjson
            events = self.events
            frames = self.frames
            use_rapidjson = True
        except:
            events = LazyList(self.events)
            frames = LazyList(self.frames)
            use_rapidjson = False

        data = {
            "$schema": "https://www.speedscope.app/file-format-schema.json",
            "profiles": [
                {
                    "type": "evented",
                    "name": "python",
                    "unit": "nanoseconds",
                    "startValue": int(self._begin_time * 1e9),
                    "endValue": int(self._end_time * 1e9),
                    "events": self.events,
                }
            ],
            "shared": {"frames": self.frames},
            "activeProfileIndex": 0,
            "exporter": "pyspeedscope",
            "name": "profile for python script",
        }
        if use_rapidjson:
            rapidjson.dump(data, filename_or_stream)
        else:
            import json
            encoder = json.JSONEncoder()
            for chunk in encoder.iterencode(data):
                filename_or_stream.write(chunk)