# this file contains common config that is sourced by all makefiles
VERSION=1.1.0.4
ARCH=all
SWDEST=$(shell pwd)/..

# platform specific definition
SSMPACKAGE=xflow_${VERSION}_$(ARCH)
