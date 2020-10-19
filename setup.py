import sys
from setuptools import setup
from distutils.extension import Extension

setup_kwargs = dict(
    name="speedscope",
    description="A python package for using speedscope.app",
    author="Windel Bouwman",
    author_email="windel.bouwman@gmail.com",
    version="1.0",
    py_modules=["speedscope"],
)

if 'build_ext' in sys.argv:
    from Cython.Build import cythonize
    import Cython.Compiler.Options
    Cython.Compiler.Options.annotate = True
    setup_kwargs['ext_modules'] = cythonize('cspeedscope.pyx', annotate=True)
else:
    setup_kwargs['ext_modules'] = [
        Extension("cspeedscope", ["cspeedscope.c"]),
    ]


setup(**setup_kwargs)
