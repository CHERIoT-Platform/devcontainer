#!/bin/sh
xmake --version --root | grep 'xmake v3.0.0+20250615,'
if [ $? -eq 0 ] ; then
	echo "Broken xmake found, patching..."
	patch /usr/share/xmake/modules/private/action/build/build_binary.lua < /tmp/xmake.diff
fi
