# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit meson xdg

DESCRIPTION="Display and control your Android device"
HOMEPAGE="https://github.com/Genymobile/scrcpy"
# Source code and server part on Android device
SRC_URI="
	https://github.com/Genymobile/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/Genymobile/${PN}/releases/download/v${PV}/${PN}-server-v${PV}
"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~ppc64 ~x86"
IUSE="X wayland"

DEPEND="
	media-libs/libsdl2[X?,wayland?]
	media-video/ffmpeg:=
	virtual/libusb:1
"
# Manual install for ppc64 until bug #723528 is fixed
RDEPEND="
	${DEPEND}
	!ppc64? ( dev-util/android-tools )
"

DOCS=( {FAQ,README}.md doc/. )

src_prepare() {
	default
	rm doc/{build,develop,macos,windows}.md || die
}

src_configure() {
	local emesonargs=(
		-Dprebuilt_server="${DISTDIR}/${PN}-server-v${PV}"
	)
	meson_src_configure
}

pkg_postinst() {
	xdg_pkg_postinst

	if has_version media-video/pipewire; then
		ewarn "On pipewire systems scrcpy might not start due to a problem with libsdl2."
		ewarn "If that is the case for you start the program as follows:"
		ewarn "    $ SDL_AUDIODRIVER=pipewire scrcpy [...]"
		ewarn "For more information see https://github.com/Genymobile/scrcpy/issues/3864"
	fi
}
