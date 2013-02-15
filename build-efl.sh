#!/bin/sh

[ -z "$MAKEFLAGS" ] && export MAKEFLAGS="-j -l 10"
[ -z "$MAKE" ]      && export MAKE="chrt --idle 0 make"
####
#### Functions
####

function _pushd() {
    pushd ./$mod_dir/$1 > /dev/null
}

function _popd() {
    popd > /dev/null
}

function die() {
    echo $@
    exit 1
}

function cleanup() {
    local mod=$1

    [ -d "$mod" ] || return

    echo "cleanup $mod..."

    _pushd $mod
        if [ -f Makefile ]; then
            $MAKE uninstall > /dev/null 2>&1
            $MAKE distclean > /dev/null 2>&1
        fi
        rm -rf autom4te.cache
        git clean -d -x -f > /dev/null 2>&1
        [ -d po/ ] && git checkout po/ > /dev/null 2>&1
    _popd
}

function clone() {
    local mod=$1
    echo "clone $mod..."

    local GIT_ROOT="git://git.enlightenment.fr/vcs/svn"
    local mod_path=""

    case $mod in
        python-*)
            mod_path="BINDINGS/python"
            ;;
        epdf | libeweather | exchange | emap | emage | etrophy)
            mod_path="PROTO"
            ;;
        eskiss | e_cho | efbb | econcentration)
            mod_path="GAMES"
            ;;
        efl)
            GIT_ROOT="git://git.enlightenment.org/core"
            ;;
        *)
            mod_path=""
            ;;
    esac

    [ -z "$mod_path" ] && GIT_URI=$GIT_ROOT/$mod || GIT_URI=$GIT_ROOT/$mod_path/$mod

    $E_PROXY_CMD git clone $GIT_URI > /dev/null 2>&1 || die "Error cloning $mod from $GIT_URI"
}

function update() {
    local mod=$1

    if [ ! -d "$mod" ]; then
        clone $mod
        return
    fi

    echo "update $mod..."
    _pushd $mod
        $E_PROXY_CMD git pull --rebase > /dev/null 2>&1 || die "Error updating $mod"
    _popd
}

function prepare_build() {
    [ -z "$PREFIX" ]      && PREFIX="$HOME/install/usr"

    local arch=`which arch`
    [ $? -eq 0 ]          && ARCH=`$arch`           || ARCH=""
    [ $ARCH == "x86_64" ] && LIBDIR="$PREFIX/lib64" || LIBDIR="$PREFIX/lib"
    [ $PREFIX == "/usr" ] && SYSCONFDIR="/etc"      || SYSCONFDIR="$PREFIX/etc"
    [ $PREFIX == "/usr" ] && LOCALSTATEDIR="/var"   || LOCALSTATEDIR="$PREFIX/var"

    export PKG_CONFIG_PATH="$LIBDIR/pkgconfig:$PKG_CONFIG_PATH"
    export LD_LIBRARY_PATH="$LIBDIR:$LD_LIBRARY_PATH"
    export PATH="$PREFIX/bin:$PATH"

    CONFIG_OPTIONS="--prefix=$PREFIX --libdir=$LIBDIR --sysconfdir=$SYSCONFDIR --localstatedir=$LOCALSTATEDIR"

    E_BUILD_FLAGS="-g -O2 -W -Wall -Wextra -march=native -ffast-math -I$PREFIX/include"
    export CFLAGS="$E_BUILD_FLAGS"
    export CXXFLAGS="$E_BUILD_FLAGS"
    export LDFLAGS="-L$LIBDIR"

    ACLOCAL_INCLUDE_DIR="$PREFIX/share/aclocal"
    [ -d $ACLOCAL_INCLUDE_DIR ] || mkdir -p $ACLOCAL_INCLUDE_DIR > /dev/null 2>&1
    export ACLOCAL="aclocal -I$ACLOCAL_INCLUDE_DIR"
}

function build() {
    local mod=$1
    local mod_config_options=""
    echo "build $mod..."

    case $mod in
        efl)
            mod_config_options=" \
                --with-profile=release
                --disable-static \
                --enable-wayland \
                --enable-egl \
                --with-opengl=es \
            "
            ;;
        epdf)
            mod_config_options=" \
                --enable-poppler \
                --disable-mupdf \
            "
            ;;
        elementary)
            mod_config_options=" \
                --disable-eweather \
                --disable-emap \
                --disable-quick-launch \
            "
            ;;
        expedite)
            mod_config_options=" \
                --disable-fb \
            "
            ;;
        *)
            mod_config_options=""
            ;;
    esac

    _pushd $mod
        [ ! -f Makefile ] && E_NO_CONFIGURE=""

        if [ -z "$E_NO_CONFIGURE" ] && [ -x ./autogen.sh ]; then
            rm -f m4/libtool.m4
            NOCONFIGURE=1 ./autogen.sh >> build.log 2>&1 || die "$mod: error running autogen.sh"
            ./configure $CONFIG_OPTIONS $mod_config_options $E_CONFIG_OPTIONS >> build.log 2>&1 || die "$mod: error running configure"
        fi

        $MAKE >> build.log 2>&1 || die "$mod: error building"
        $MAKE -j 1 install >> build.log 2>&1 || die "$mod: error installing"
    _popd

}

function run_all() {
    local func=$1
    for module in $E_MODULES; do
        $func $module
    done
}

####
#### Begin
####

E_MODULES=$@

[ -z "$E_MODULES" ] && E_MODULES=" \
    efl \
    evas_generic_loaders \
    expedite \
    epdf \
    elementary \
    terminology \
"

# Cleanup (set E_NO_CLEANUP to bypass)
if [ -z "$E_NO_CLEANUP" ]; then
    run_all cleanup
fi

# Update SVN (set E_NO_UPDATE_SVN to bypass)
if [ -z "$E_NO_UPDATE" ]; then
    run_all update
fi

# Build
if [ -z "$E_NO_BUILD" ]; then
    prepare_build
    run_all build
fi
