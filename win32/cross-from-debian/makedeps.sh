#!/bin/sh -e
# Script to cross-compile Performous's dependency libraries for Win32.
# Copyright (C) 2010 John Stumpo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

die () { echo "$@" >&2 ; exit 1 ; }

assert_binary_on_path () {
  if which "$1" >/dev/null 2>&1; then
    echo found program "$1"
  else
    echo did not find "$1", which is required
    exit 1
  fi
}

assert_binary_on_path autoreconf
assert_binary_on_path i586-mingw32msvc-gcc
assert_binary_on_path make
assert_binary_on_path pkg-config
assert_binary_on_path svn
assert_binary_on_path tar
assert_binary_on_path unzip
assert_binary_on_path wget
assert_binary_on_path wine

export PREFIX="`pwd`"/deps
export WINEPREFIX="`pwd`"/wine
mkdir -pv "$PREFIX"/bin "$PREFIX"/lib "$PREFIX"/include

echo 'setting up wine environment'
wine reg add 'HKCU\Environment' /v PATH /d Z:"`echo "$PREFIX" | tr '/' '\\'`"\\bin

echo 'creating pkg-config wrapper for cross-compiled environment'
cat >"$PREFIX"/bin/pkg-config <<EOF
#!/bin/sh -e
exec env PKG_CONFIG_LIBDIR='$PREFIX'/lib/pkgconfig '`which pkg-config`' "\$@"
EOF
chmod -v 0755 "$PREFIX"/bin/pkg-config
cat >"$PREFIX"/bin/wine-shwrap <<"EOF"
#!/bin/sh -e
path="`(cd $(dirname "$1") && pwd)`/`basename "$1"`"
echo '#!/bin/bash -e' >"$1"
echo 'wine '"$path"'.exe "$@" | tr -d '"'\\\015'" >>"$1"
echo 'exit ${PIPESTATUS[0]}' >>"$1"
chmod 0755 "$1"
EOF
chmod 0755 $PREFIX/bin/wine-shwrap

export PATH="$PREFIX"/bin:"$PATH"

download () {
  basename="`basename "$1"`"
  if test ! -f "$basename"; then
    wget -c -O "$basename".part "$1"
    mv -v "$basename".part "$basename"
  fi
}

gunzip -cf /usr/share/doc/mingw32-runtime/mingwm10.dll.gz >"$PREFIX"/bin/mingwm10.dll

download http://win-iconv.googlecode.com/files/win-iconv-0.0.1.tar.bz2
tar jxvf win-iconv-0.0.1.tar.bz2
cd win-iconv-0.0.1
make clean
make -n iconv.dll win_iconv.exe | sed -e 's/^/i586-mingw32msvc-/' | sh -ex
i586-mingw32msvc-gcc -mdll -o iconv.dll -Wl,--out-implib,libiconv.a iconv.def win_iconv.o
cp -v iconv.dll win_iconv.exe "$PREFIX"/bin
cp -v iconv.h "$PREFIX"/include
echo '' >>"$PREFIX"/include/iconv.h  # squelch warnings about no newline at the end
sed -i -e 's://.*$::' "$PREFIX"/include/iconv.h  # squelch warnings about C++ comments
cp -v libiconv.a "$PREFIX"/lib
cd ..

download http://www.zlib.net/zlib-1.2.5.tar.bz2
tar jxvf zlib-1.2.5.tar.bz2
cd zlib-1.2.5
make -f win32/Makefile.gcc PREFIX=i586-mingw32msvc- zlib1.dll
cp -v zlib.h zconf.h "$PREFIX"/include
cp -v zlib1.dll "$PREFIX"/bin
cp -v libzdll.a "$PREFIX"/lib/libz.a
cd ..

download http://download.sourceforge.net/libpng/libpng-1.4.2.tar.gz
tar zxvf libpng-1.4.2.tar.gz
cd libpng-1.4.2
make -f scripts/makefile.mingw prefix="$PREFIX" CC=i586-mingw32msvc-gcc AR=i586-mingw32msvc-ar RANLIB=i586-mingw32msvc-ranlib ZLIBINC="$PREFIX"/include ZLIBLIB="$PREFIX"/lib install-shared
cd ..

download http://www.ijg.org/files/jpegsrc.v8b.tar.gz
tar zxvf jpegsrc.v8b.tar.gz
cd jpeg-8b
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared
make
make install
cd ..

download http://ftp.gnu.org/gnu/gettext/gettext-0.18.tar.gz
tar zxvf gettext-0.18.tar.gz
cd gettext-0.18/gettext-runtime
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared --enable-relocatable --disable-libasprintf --disable-java --disable-csharp CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ../..

download ftp://xmlsoft.org/libxml2/libxml2-2.7.7.tar.gz
tar zxvf libxml2-2.7.7.tar.gz
cd libxml2-2.7.7
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared --without-python --without-readline CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://download.sourceforge.net/boost/boost_1_43_0.tar.bz2
tar jxvf boost_1_43_0.tar.bz2
cd boost_1_43_0/tools/jam/src
./build.sh
cp -v bin.linux*/bjam ../../..
cd ../../..
cat >>tools/build/v2/user-config.jam <<EOF
using gcc : debian_mingw32_cross : i586-mingw32msvc-g++ ;
EOF
./bjam --prefix="$PREFIX" --with-filesystem --with-system --with-thread --with-date_time --with-program_options --with-regex toolset=gcc-debian_mingw32_cross target-os=windows variant=release link=shared runtime-link=shared threading=multi threadapi=win32 stage
cp -av boost "$PREFIX"/include
cp -v stage/lib/*.dll "$PREFIX"/bin
cp -v stage/lib/*.a "$PREFIX"/lib
ln -svf libboost_thread_win32.dll.a "$PREFIX"/lib/libboost_thread.dll.a
cd ..

download http://www.libsdl.org/extras/win32/common/directx-source.tar.gz
tar zxvf directx-source.tar.gz
cd directx
sed -i -e 's/dlltool /i586-mingw32msvc-&/' -e 's/ar /i586-mingw32msvc-&/' lib/Makefile
make -C lib distclean
make -C lib CC=i586-mingw32msvc-gcc
cp -v include/*.h "$PREFIX"/include
cp -v lib/*.a "$PREFIX"/lib
cd ..

if test ! -f portaudio/svn-stamp; then
  svn co -r 1433 http://www.portaudio.com/repos/portaudio/trunk portaudio
  echo 1433 >portaudio/svn-stamp
else
  if test x"`svn info portaudio | grep '^Revision: '`" != x"Revision: `cat portaudio/svn-stamp`"; then
    svn revert portaudio/configure portaudio/configure.in
    svn up -r "`cat portaudio/svn-stamp`" portaudio
  fi
fi
cd portaudio
echo 'Patching mingw host triplet pattern matching bug in configure.'
sed -i -e 's/\**mingw\*.*)/\*&/' configure.in
autoreconf
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared --with-winapi=directx --with-dxdir="$PREFIX"
make
make install
cd ..

download http://download.sourceforge.net/portmedia/portmidi-src-200.zip
unzip -o portmidi-src-200.zip
cd portmidi
i586-mingw32msvc-gcc -g -O2 -W -Wall -Ipm_common -Iporttime -DNDEBUG -D_WINDLL -mdll -o portmidi.dll -Wl,--out-implib,libportmidi.a pm_win/pmwin.c pm_win/pmwinmm.c porttime/ptwinmm.c pm_common/pmutil.c pm_common/portmidi.c -lwinmm
cp -v portmidi.dll "$PREFIX"/bin
cp -v libportmidi.a "$PREFIX"/lib
cp -v pm_common/portmidi.h porttime/porttime.h "$PREFIX"/include
cd ..

download http://www.libsdl.org/release/SDL-1.2.14.tar.gz
tar zxvf SDL-1.2.14.tar.gz
cd SDL-1.2.14
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://download.sourceforge.net/freetype/freetype-2.3.12.tar.bz2
tar jxvf freetype-2.3.12.tar.bz2
cd freetype-2.3.12/builds/unix
cd ../..
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://ftp.gnome.org/pub/GNOME/sources/glib/2.24/glib-2.24.1.tar.bz2
tar jxvf glib-2.24.1.tar.bz2
cd glib-2.24.1
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make -C glib
make -C gthread
make -C gobject glib-genmarshal.exe
wine-shwrap gobject/glib-genmarshal
make
make install
cd ..

download http://fontconfig.org/release/fontconfig-2.8.0.tar.gz
tar zxvf fontconfig-2.8.0.tar.gz
cd fontconfig-2.8.0
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
wine-shwrap "$PREFIX"/bin/fc-cache
make install
rm -f "$PREFIX"/bin/fc-cache
cd ..

download http://cairographics.org/releases/pixman-0.18.2.tar.gz
tar zxvf pixman-0.18.2.tar.gz
cd pixman-0.18.2
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://cairographics.org/releases/cairo-1.8.10.tar.gz
tar zxvf cairo-1.8.10.tar.gz
cd cairo-1.8.10
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared --disable-xlib CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://ftp.gnome.org/pub/GNOME/sources/pango/1.28/pango-1.28.1.tar.bz2
tar jxvf pango-1.28.1.tar.bz2
cd pango-1.28.1
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared --with-included-modules=yes --with-dynamic-modules=no CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" CXX='i586-mingw32msvc-g++ "-D__declspec(x)=__attribute__((x))"'
make
make install
for f in '' cairo ft2 win32; do
  mv "$PREFIX"/lib/libpango$f-1.0-0.dll "$PREFIX"/bin
  rm -f "$PREFIX"/lib/libpango$f-1.0.lib
  i586-mingw32msvc-dlltool -D libpango$f-1.0-0.dll -d "$PREFIX"/lib/pango$f-1.0.def -l "$PREFIX"/lib/libpango$f-1.0.a
  sed -i -e "s/libpango$f-1.0.lib/libpango$f-1.0.a/g" "$PREFIX"/lib/libpango$f-1.0.la
done
cd ..

download http://ftp.acc.umu.se/pub/GNOME/sources/atk/1.30/atk-1.30.0.tar.bz2
tar jxvf atk-1.30.0.tar.bz2
cd atk-1.30.0
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://ftp.acc.umu.se/pub/GNOME/sources/gtk+/2.20/gtk+-2.20.1.tar.bz2
tar jxvf gtk+-2.20.1.tar.bz2
cd gtk+-2.20.1
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared --disable-modules --without-libtiff --with-included-loaders=png,jpeg,gif,xpm,xbm CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make -C gdk-pixbuf
wine-shwrap gdk-pixbuf/gdk-pixbuf-csource
wine-shwrap gdk-pixbuf/gdk-pixbuf-query-loaders
make -C gdk
make -C gtk gtk-update-icon-cache.exe
wine-shwrap gtk/gtk-update-icon-cache
make -C gtk gtk-query-immodules-2.0.exe
wine-shwrap gtk/gtk-query-immodules-2.0
make
make install
find "$PREFIX"/lib/gtk-2.0 -name '*.la' -print0 | xargs -0 rm -f
find "$PREFIX"/lib/gtk-2.0 -name '*.dll.a' -print0 | xargs -0 rm -f
cp "$PREFIX"/share/themes/MS-Windows/gtk-2.0/gtkrc "$PREFIX"/etc/gtk-2.0
cd ..

download http://ftp.gnome.org/pub/GNOME/sources/libcroco/0.6/libcroco-0.6.2.tar.bz2
tar jxvf libcroco-0.6.2.tar.bz2
cd libcroco-0.6.2
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://ftp.acc.umu.se/pub/GNOME/sources/libgsf/1.14/libgsf-1.14.18.tar.bz2
tar jxvf libgsf-1.14.18.tar.bz2
cd libgsf-1.14.18
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared --without-python --disable-schemas-install CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://ftp.acc.umu.se/pub/GNOME/sources/librsvg/2.26/librsvg-2.26.3.tar.bz2
tar jxvf librsvg-2.26.3.tar.bz2
cd librsvg-2.26.3
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared --disable-pixbuf-loader --disable-gtk-theme CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://ftp.acc.umu.se/pub/GNOME/sources/libsigc++/2.2/libsigc++-2.2.8.tar.bz2
tar jxvf libsigc++-2.2.8.tar.bz2
cd libsigc++-2.2.8
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://ftp.acc.umu.se/pub/GNOME/sources/glibmm/2.24/glibmm-2.24.2.tar.bz2
tar jxvf glibmm-2.24.2.tar.bz2
cd glibmm-2.24.2
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://ftp.acc.umu.se/pub/GNOME/sources/libxml++/2.30/libxml++-2.30.1.tar.bz2
tar jxvf libxml++-2.30.1.tar.bz2
cd libxml++-2.30.1
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://download.sourceforge.net/glew/glew-1.5.4.tgz
tar zxvf glew-1.5.4.tgz
cd glew-1.5.4
i586-mingw32msvc-windres -o glewres.o build/vc6/glew.rc
i586-mingw32msvc-gcc -g -O2 -W -Wall -Iinclude -DGLEW_BUILD -mdll -Wl,--out-implib,libGLEW.a -o glew32.dll src/glew.c glewres.o -lopengl32 -lglu32 -lgdi32
i586-mingw32msvc-windres -o glewinfores.o build/vc6/glewinfo.rc
i586-mingw32msvc-gcc -g -O2 -W -Wall -Iinclude -o glewinfo.exe src/glewinfo.c glewinfores.o -L. -lGLEW -lopengl32 -lglu32 -lgdi32
i586-mingw32msvc-windres -o visualinfores.o build/vc6/visualinfo.rc
i586-mingw32msvc-gcc -g -O2 -W -Wall -Iinclude -o visualinfo.exe src/visualinfo.c visualinfores.o -L. -lGLEW -lopengl32 -lglu32 -lgdi32
make GLEW_DEST="$PREFIX" glew.pc
cp -v glew32.dll glewinfo.exe visualinfo.exe "$PREFIX"/bin
cp -v libGLEW.a "$PREFIX"/lib
mkdir -pv "$PREFIX"/include/GL "$PREFIX"/lib/pkgconfig
cp -v include/GL/* "$PREFIX"/include/GL
cp -v glew.pc "$PREFIX"/lib/pkgconfig
cd ..

download http://code.entropywave.com/download/orc/orc-0.4.5.tar.gz
tar zxvf orc-0.4.5.tar.gz
cd orc-0.4.5
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

download http://diracvideo.org/download/schroedinger/schroedinger-1.0.9.tar.gz
tar zxvf schroedinger-1.0.9.tar.gz
cd schroedinger-1.0.9
./configure --prefix="$PREFIX" --host=i586-mingw32msvc --disable-static --enable-shared CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
make
make install
cd ..

if test ! -d ffmpeg; then
  svn co svn://svn.ffmpeg.org/ffmpeg/trunk ffmpeg
else
  svn up ffmpeg
fi
cd ffmpeg
./configure --prefix="$PREFIX" --cc=i586-mingw32msvc-gcc --nm=i586-mingw32msvc-nm --target-os=mingw32 --arch=i386 --disable-static --enable-shared --enable-gpl --enable-postproc --enable-avfilter-lavf --enable-w32threads --enable-runtime-cpudetect --enable-memalign-hack --enable-zlib --enable-libschroedinger --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib"
sed -i -e 's/-Werror=[^ ]*//g' config.mak
make
make install
for lib in avcodec avdevice avfilter avformat avutil postproc swscale; do
  find "$PREFIX"/bin -type l -name "${lib}*.dll" -print0 | xargs -0 rm -f
  libfile="`find "$PREFIX"/bin -name "${lib}*.dll" | sed -e 1q`"
  mv -v "$libfile" "`echo "$libfile" | sed -e "s/\($lib-[0-9]*\)[.0-9]*\.dll/\1.dll/"`"
done
cd ..