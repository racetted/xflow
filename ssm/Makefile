# ATTENTION!
# YOU NEED TO USE THE GMAKE IN /users/dor/afsi/sul/ovbin/gmake for this
# Makefile to work, other versions installed are currently too old!
#
# common section definition
include config.mk

ssm: profile.sh
	echo "Creating SSM package $(SSMPACKAGE)..."
	if [ ! -d $(SSMPACKAGE) ]; then \
	   mkdir $(SSMPACKAGE); \
	fi;
	cp -r $(SWDEST)/bin $(SSMPACKAGE); 
	cp -r $(SWDEST)/lib $(SSMPACKAGE); 
	cp -r $(SWDEST)/etc $(SSMPACKAGE); 
	mkdir -p $(SSMPACKAGE)/.ssm.d;
	cp -r post-install $(SSMPACKAGE)/.ssm.d;
	cp -r profile.sh $(SSMPACKAGE)/.ssm.d;
	echo "Package: xflow" > $(SSMPACKAGE)/.ssm.d/control; \
	echo "Version: ${VERSION}" >> $(SSMPACKAGE)/.ssm.d/control; \
	echo "Platform: all" >> $(SSMPACKAGE)/.ssm.d/control; \
	echo "Maintainer: $(shell whoami)" >> $(SSMPACKAGE)/.ssm.d/control; \
	echo "BuildInfo:" >> $(SSMPACKAGE)/.ssm.d/control; \
	echo "Description: Unified Tasks Monitor" >> $(SSMPACKAGE)/.ssm.d/control; \
	tar cvf - $(SSMPACKAGE) | gzip -> $(SSMPACKAGE).ssm

profile.sh: Makefile config.mk
	echo "export SEQ_XFLOW_VERSION=${VERSION}" >$@

clean:
	rm -fr profile.sh $(SSMPACKAGE).ssm $(SSMPACKAGE)
