# Copyright 2023-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

LLVM_COMPAT=( {15..20} )
LLVM_OPTIONAL=1
PYTHON_COMPAT=( python3_{11..13} )
inherit cmake edo flag-o-matic go-env llvm-r2 multiprocessing
inherit python-any-r1 readme.gentoo-r1 xdg

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI=(
		"https://code.qt.io/qt-creator/qt-creator.git"
		"https://github.com/qt-creator/qt-creator.git"
	)
	EGIT_SUBMODULES=(
		perfparser
		src/libs/qlitehtml
		src/libs/qlitehtml/src/3rdparty/litehtml
	)
else
	QTC_PV=${PV/_/-}
	QTC_P=${PN}-opensource-src-${QTC_PV}
	[[ ${QTC_PV} == ${PV} ]] && QTC_REL=official || QTC_REL=development
	SRC_URI="
		https://download.qt.io/${QTC_REL}_releases/qtcreator/$(ver_cut 1-2)/${PV/_/-}/${QTC_P}.tar.xz
		cmdbridge-server? ( https://dev.gentoo.org/~ionen/distfiles/${QTC_P}-vendor.tar.xz )
	"
	S=${WORKDIR}/${QTC_P}
	KEYWORDS="amd64"
fi

DESCRIPTION="Lightweight IDE for C++/QML development centering around Qt"
HOMEPAGE="https://www.qt.io/product/development-tools"

LICENSE="GPL-3"
LICENSE+=" BSD MIT" # go
SLOT="0"
IUSE="
	+clang cmdbridge-server designer doc +help keyring plugin-dev
	qmldesigner serialterminal +svg test +tracing webengine
"
REQUIRED_USE="clang? ( ${LLVM_REQUIRED_USE} )"
RESTRICT="!test? ( test )"

QT_PV=6.7.3:6

# := is used where Qt's private APIs are used for safety
COMMON_DEPEND="
	app-arch/libarchive:=
	dev-cpp/yaml-cpp:=
	>=dev-qt/qt5compat-${QT_PV}
	>=dev-qt/qtbase-${QT_PV}=[concurrent,dbus,gui,network,ssl,widgets,xml]
	>=dev-qt/qtdeclarative-${QT_PV}=
	clang? (
		$(llvm_gen_dep '
			llvm-core/clang:${LLVM_SLOT}=
			llvm-core/llvm:${LLVM_SLOT}=
		')
	)
	designer? ( >=dev-qt/qttools-${QT_PV}[designer] )
	help? (
		>=dev-qt/qttools-${QT_PV}[assistant]
		webengine? ( >=dev-qt/qtwebengine-${QT_PV} )
	)
	keyring? (
		app-crypt/libsecret
		dev-libs/glib:2
	)
	qmldesigner? (
		>=dev-qt/qtquick3d-${QT_PV}=
		>=dev-qt/qtsvg-${QT_PV}
		>=dev-qt/qtwebsockets-${QT_PV}
		webengine? ( >=dev-qt/qtwebengine-${QT_PV} )
	)
	serialterminal? ( >=dev-qt/qtserialport-${QT_PV} )
	svg? ( >=dev-qt/qtsvg-${QT_PV} )
	tracing? (
		app-arch/zstd:=
		dev-libs/elfutils
		>=dev-qt/qtcharts-${QT_PV}
		>=dev-qt/qtshadertools-${QT_PV}
	)
"
# qtimageformats for .webp in examples, semi-optfeature but useful in general
RDEPEND="
	${COMMON_DEPEND}
	help? ( >=dev-qt/qtimageformats-${QT_PV} )
	qmldesigner? ( >=dev-qt/qtquicktimeline-${QT_PV} )
"
DEPEND="${COMMON_DEPEND}"
# intentionally skipping := on go (unlike go-module.eclass) given not
# worth a massive rebuild every time for the minor go usage
BDEPEND="
	${PYTHON_DEPS}
	>=dev-qt/qttools-${QT_PV}[linguist]
	cmdbridge-server? ( >=dev-lang/go-1.21.7 )
	doc? ( >=dev-qt/qttools-${QT_PV}[qdoc,qtattributionsscanner] )
"

PATCHES=(
	"${FILESDIR}"/${PN}-16.0.0-musl-no-execinfo.patch
	"${FILESDIR}"/${PN}-12.0.0-musl-no-malloc-trim.patch
)

# written in Go, use PREBUILT rather than FLAGS_IGNORED given the
# the different arch versions confuse portage's checks
QA_PREBUILT="usr/libexec/qtcreator/cmdbridge-*"

src_unpack() {
	if [[ ${PV} == 9999 ]]; then
		git-r3_src_unpack
		if use cmdbridge-server; then
			cd -- "${S}"/src/libs/gocmdbridge/server || die
			edo go mod vendor
		fi
	else
		default
	fi
}

src_prepare() {
	cmake_src_prepare

	# needed for finding docs at runtime in PF
	sed -e "/_IDE_DOC_PATH/s/qtcreator/${PF}/" \
		-i cmake/QtCreatorAPIInternal.cmake || die

	# avoid stripping for Go, use sed to avoid rebases as may be there forever
	sed -i 's/-s -w //' src/libs/gocmdbridge/server/CMakeLists.txt || die

	# avoid building manual tests (aka not ran) for nothing (bug #950010)
	sed -i '/add_subdirectory(manual)/d' tests/CMakeLists.txt || die

	if use plugin-dev; then #928423
		# cmake --install --component integrates poorly with the cmake
		# eclass and the install targets are otherwise missing, so strip
		# out EXCLUDE_FROM_ALL until figure out a better solution
		find . \( -name CMakeLists.txt -o -name '*.cmake' \) -exec sed -i -zE \
			's/COMPONENT[[:space:]]+Devel[[:space:]]+EXCLUDE_FROM_ALL//g' {} + || die
	fi
}

src_configure() {
	use clang && llvm_chost_setup

	if use cmdbridge-server; then
		go-env_set_compile_environment
		export GOFLAGS="-p=$(makeopts_jobs) -v -x -buildvcs=false -buildmode=pie"
	fi

	# -Werror=lto-type-mismatch issues, needs looking into
	filter-lto

	# temporary workaround for musl-1.2.4 (bug #903611), this ideally
	# needs fixing in qtbase as *64 usage comes from its headers' macros
	use elibc_musl && append-lfs-flags

	local mycmakeargs=(
		-DBUILD_DEVELOPER_DOCS=$(usex doc)
		-DBUILD_DOCS_BY_DEFAULT=$(usex doc)
		-DBUILD_WITH_PCH=no
		-DWITH_DOCS=$(usex doc)
		-DWITH_TESTS=$(usex test)

		# sticking to bundled for now until it switches to KF6's
		-DBUILD_LIBRARY_KSYNTAXHIGHLIGHTING=yes

		# Much can be optional, but do not want to flood users (or maintainers)
		# with too many flags. Not to mention that many plugins are merely
		# wrappers around still optional tools (e.g. cvs) and any unwanted
		# plugins can be disabled at runtime. So optional flags are limited
		# to plugins with additional build-time dependencies.
		-DBUILD_LIBRARY_TRACING=$(usex tracing) # qml+perfprofiler,ctfvisual
		-DBUILD_EXECUTABLE_PERFPARSER=$(usex tracing)
		-DBUILD_PLUGIN_APPSTATISTICSMONITOR=$(usex tracing)

		-DBUILD_PLUGIN_CLANGCODEMODEL=$(usex clang)
		-DBUILD_PLUGIN_CLANGFORMAT=$(usex clang)
		-DBUILD_PLUGIN_CLANGTOOLS=$(usex clang)
		-DCLANGTOOLING_LINK_CLANG_DYLIB=yes

		-DBUILD_PLUGIN_DESIGNER=$(usex designer)

		-DBUILD_PLUGIN_HELP=$(usex help)
		-DBUILD_HELPVIEWERBACKEND_QTWEBENGINE=$(usex webengine)
		-DBUILD_LIBRARY_QLITEHTML=$(usex help $(usex !webengine))
		# TODO?: package litehtml, but support for latest releases seem
		# to lag behind and bundled may work out better for now
		# https://bugreports.qt.io/browse/QTCREATORBUG-29169
		$(use help && usev !webengine -DCMAKE_DISABLE_FIND_PACKAGE_litehtml=yes)

		# help shouldn't use with the above, but qmldesigner is automagic
		$(use help || use qmldesigner &&
			cmake_use_find_package webengine Qt6WebEngineWidgets)

		-DBUILD_PLUGIN_SERIALTERMINAL=$(usex serialterminal)
		-DENABLE_SVG_SUPPORT=$(usex svg)
		$(usev !cmdbridge-server -DGO_BIN=GO_BIN-NOTFOUND) #945925
		-DWITH_QMLDESIGNER=$(usex qmldesigner)

		# meant to be in sync with qtbase[journald], but think(?) not worth
		# handling given qt-creator can use QT_FORCE_STDERR_LOGGING=1 nowadays
		-Djournald=no

		# not packaged, but allow using if found
		#-DCMAKE_DISABLE_FIND_PACKAGE_LibDDemangle=yes
		#-DCMAKE_DISABLE_FIND_PACKAGE_LibRustcDemangle=yes

		# for bundled qtkeychain (no switch to unbundle right now)
		# reminder: if ever unbundled/optional, qtbase[dbus] can be removed
		-DLIBSECRET_SUPPORT=$(usex keyring)
	)

	cmake_src_configure
}

src_test() {
	local -x QT_QPA_PLATFORM=offscreen

	local CMAKE_SKIP_TESTS=(
		# tst_Process::recursiveBlockingProcess() broke in 17.0.0, not really looked
		# into yet but does not seem to cause visible issues, skip for now (unknown
		# if it passes upstream given their CI is failing to run tests right now)
		tst_process
		# skipping same tests+label as upstream's CI by default
		# `grep ctest .github/workflows/build_cmake.yml`
		tst_perfdata
	)

	cmake_src_test --label-exclude exclude_from_precheck
}

src_install() {
	cmake_src_install

	if use doc; then
		dodoc -r "${BUILD_DIR}"/doc/html
		dodoc "${BUILD_DIR}"/share/doc/${PF}/qtcreator{,-dev}.qch
		docompress -x /usr/share/doc/${PF}/qtcreator{,-dev}.qch
	fi

	local DISABLE_AUTOFORMATTING=yes
	local DOC_CONTENTS="\
Some plugins (if used) may need optional extra dependencies/USE.

This list provides associations with Gentoo's packages (if exists)
ordered as in Qt Creator's Help -> About Plugins (not exhaustive).

dev-qt/qt-docs:6 with USE=\"examples qch\" is notably recommended, or
else the example tab will be empty alongside missing documentation.

Build Systems:
- CMakeProjectManager (dev-build/cmake)
- MesonProjectManager (dev-build/meson)
- QbsProjectManager (dev-util/qbs)

C++:
- Beautifier (dev-util/astyle and/or dev-util/uncrustify)
- ClangCodeModel (USE=clang, dev-util/clazy to understand Qt semantics)
- ClangFormat (USE=clang)

Code Analyzer:
- ClangTools (USE=clang)
- Cppcheck (dev-util/cppcheck)
- CtfVisualizer (USE=tracing)
- PerfProfiler (USE=tracing)
- Valgrind (dev-debug/valgrind)

Core:
- Help (USE=help + dev-qt/qt-docs:6 with USE=\"examples qch\")

Device Support:
- Android (virtual/jdk, will also want the unpackaged Qt for Android)

Other Languages:
- Nim (dev-lang/nim)
- Python (dev-lang/python)

Qt Creator:
- Designer (USE=designer)

Qt Quick:
- Insight (USE=qmldesigner)
- QmlDesigner (USE=qmldesigner)
- QmlProfiler (USE=tracing)

Utilities:
- AppStatisticsMonitor (USE=tracing)
- Autotest (dev-cpp/catch, dev-cpp/gtest, or dev-libs/boost if used)
- Conan (dev-util/conan)
- Docker (app-containers/docker)
- Haskell (dev-lang/ghc)
- ScreenRecorder (media-video/ffmpeg)
- SerialTerminal (USE=serialterminal)
- SilverSearcher (sys-apps/the_silver_searcher)
- StudioWelcome (USE=qmldesigner)

Version Control:
- CVS (dev-vcs/cvs)
- Fossil (dev-vcs/fossil)
- Git (dev-vcs/git)
- Mercurial (dev-vcs/mercurial)
- Subversion (dev-vcs/subversion)"
	readme.gentoo_create_doc
}

pkg_postinst() {
	xdg_pkg_postinst
	readme.gentoo_print_elog
}
