#!/bin/sh -e
# Copyright (c) 2023 Roger Brown.
# Licensed under the MIT License.

PACKAGE=scdoc
VERSION=1.11.0
RELEASE=1

if test -z "$MAINTAINER"
then
	if git config user.email > /dev/null
	then
		MAINTAINER="$(git config user.email)"
	else
		echo MAINTAINER not set 1>&2
		false
	fi
fi

mkdir work

cleanup()
{
	chmod -R +w work
	rm -rf work scdoc rpms rpm.spec
}

trap cleanup 0

git -c advice.detachedHead=false clone --single-branch --branch "$VERSION" https://github.com/ddevault/scdoc.git scdoc

(
	set -e

	cd scdoc

	make LDFLAGS=-lc PREFIX=/usr 

	make install DESTDIR=$(pwd)/../work PREFIX=/usr 
)

ldd work/usr/bin/scdoc

(
	set -e

	cd work

	mkdir -p control data/usr

	find usr/share -type f | xargs chmod gou-x 

	strip usr/bin/scdoc

	mv usr/bin data/usr/bin

	mv usr/share data/usr

	find data/usr/share/man -type f | while read N
	do
		gzip "$N"
	done

	chmod -R -w data

	if dpkg --print-architecture
	then
		DPKGARCH=$(dpkg --print-architecture)

		SIZE=$( du -sk data | while read A B; do echo $A; done)

		cat > control/control <<EOF
Package: $PACKAGE
Version: $VERSION-$RELEASE
Architecture: $DPKGARCH
Installed-Size: $SIZE
Maintainer: $MAINTAINER
Section: utils
Priority: extra
Description: scdoc is a simple man page generator for POSIX systems written in C99.
EOF

		for d in data control
		do
			(
				set -e

				cd "$d"

				tar --owner=0 --group=0 --create --xz --file "../$d.tar.xz" $(find * -type f)
			)
		done

		echo "2.0" >debian-binary

		ar r "$PACKAGE"_"$VERSION-$RELEASE"_"$DPKGARCH".deb debian-binary control.tar.* data.tar.*

		mv *.deb ..
	fi
)

if rpmbuild --version
then
	cat > rpm.spec <<EOF
Summary: scdoc is a simple man page generator for POSIX systems written in C99.
Name: $PACKAGE
Version: $VERSION
Release: $RELEASE
Group: Development/Tools
License: MIT
Packager: $MAINTAINER
Autoreq: 0
AutoReqProv: no
Prefix: /

%description
scdoc is a simple man page generator for POSIX systems written in C99.

%files
%defattr(-,root,root)
/usr/bin/scdoc
/usr/share/man/man1/scdoc.1.gz
/usr/share/man/man5/scdoc.5.gz

%clean

EOF

	PWD=`pwd`

	rpmbuild --buildroot "$PWD/work/data" --define "_rpmdir $PWD/rpms" -bb "$PWD/rpm.spec" --define "_build_id_links none" 

	find rpms -type f -name "*.rpm" | while read N
	do
		mv "$N" .
		basename "$N"
	done
fi
