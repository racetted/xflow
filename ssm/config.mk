# this file contains common config that is sourced by all makefiles
VERSION=1.3.1.2
ARCH=all
SWDEST=$(shell pwd)/..

# platform specific definition
SSMPACKAGE=xflow_${VERSION}_$(ARCH)
