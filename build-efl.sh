#!/bin/sh

[ -z "$MAKEFLAGS" ] && export MAKEFLAGS="-j -l 10"
[ -z "$MAKE" ]      && export MAKE="chrt --idle 0 make"
[ -z "$E_VERBOSE" ] && export OUTPUT="/dev/null" BUILD_OUTPUT="build.log" || export OUTPUT="/dev/stdout" BUILD_OUTPUT="/dev/stdout"
####
#### Functions
####

function _pushd() {
    pushd ./$mod_dir/$1 > $OUTPUT
}

function _popd() {
    popd > $OUTPUT
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
            sudo $MAKE uninstall > $OUTPUT 2>&1
            sudo $MAKE distclean > $OUTPUT 2>&1
        fi
        rm -rf autom4te.cache
        sudo git clean -d -x -f > $OUTPUT 2>&1
        [ -d po/ ] && git checkout po/ > $OUTPUT 2>&1
    _popd
}

function clone() {
    local mod=$1
    echo "clone $mod..."

    local GIT_ROOT="ssh://git@git.enlightenment.org"
    local mod_path="core"

    case $mod in
        python-*)
            mod_path="legacy/bindings/python"
            ;;
        libeweather )
            mod_path="libs"
            ;;
        e_cho | efbb | econcentration | elemines | etrophy | eskiss )
            mod_path="games"
            ;;
        engage | comp-scale | forecasts )
            mod_path="enlightenment/modules"
            ;;
        ephoto | enjoy | ecrire | equate | terminology | eruler | rage | empc )
            mod_path="apps"
            ;;
        closeau | expedite)
            mod_path="tools"
            ;;
        maelstrom )
            mod_path="devs/discomfitor"
            ;;
    esac

    [ -z "$mod_path" ] && GIT_URI=$GIT_ROOT/$mod || GIT_URI=$GIT_ROOT/$mod_path/$mod

    $E_PROXY_CMD git clone $GIT_URI > $OUTPUT 2>&1 || die "Error cloning $mod from $GIT_URI"
    ctags -R
}

function update() {
    local mod=$1

    if [ ! -d "$mod" ]; then
        clone $mod
        return
    fi

    echo "update $mod..."
    _pushd $mod
        git co po > $OUTPUT 2>&1
        $E_PROXY_CMD git pull --rebase > $OUTPUT 2>&1 || die "Error updating $mod"
        git gc > $OUTPUT 2>&1
        ctags -R > $OUTPUT 2>&1
    _popd
}

function prepare_build() {
    local arch=`which arch`

    [ -z "$PREFIX" ]      && PREFIX="/usr"
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
    [ -d $ACLOCAL_INCLUDE_DIR ] || mkdir -p $ACLOCAL_INCLUDE_DIR > $OUTPUT 2>&1
    export ACLOCAL="aclocal -I$ACLOCAL_INCLUDE_DIR"
}

function build() {
    local mod=$1
    local mod_config_options=""
    echo "build $mod..."

    case $mod in
        efl)
            mod_config_options=" \
                --with-profile=dev \
                --enable-egl \
                --with-opengl=es \
                --enable-wayland \
                --enable-systemd \
            "
            ;;
        epdf)
            mod_config_options=" \
                --enable-poppler \
                --disable-mupdf \
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
            NOCONFIGURE=1 ./autogen.sh >> $BUILD_OUTPUT 2>&1 || die "$mod: error running autogen.sh"
            ./configure $CONFIG_OPTIONS $mod_config_options $E_CONFIG_OPTIONS >> $BUILD_OUTPUT 2>&1 || die "$mod: error running configure"
        fi

        $MAKE >> $BUILD_OUTPUT 2>&1 || die "$mod: error building"
        sudo $MAKE -j 1 install >> $BUILD_OUTPUT 2>&1 || die "$mod: error installing"
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

[ -z "$E_MODULES" ] && E_MODULES=$@
[ -z "$E_MODULES" ] && E_MODULES=" \
    efl \
    evas_generic_loaders \
    emotion_generic_players \
    eruler \
    terminology \
    rage \
    enlightenment \
    maelstrom \
    empc \
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
