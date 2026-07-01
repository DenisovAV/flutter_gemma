import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../theme/brand.dart';

/// Sticky top navigation bar.
///
/// Client component because the mobile menu toggles open/closed. On wide
/// screens the links render inline and the hamburger is hidden via CSS; on
/// narrow screens the links collapse into a toggleable dropdown.
@client
class NavBar extends StatefulComponent {
  const NavBar({super.key});

  @override
  State<NavBar> createState() => NavBarState();
}

class NavBarState extends State<NavBar> {
  bool _open = false;

  static const _links = <({String text, String href, bool external, bool cta})>[
    (text: 'Docs', href: '/docs/getting-started', external: false, cta: false),
    (text: 'Models', href: '#models', external: false, cta: false),
    (
      text: 'GitHub',
      href: 'https://github.com/DenisovAV/flutter_gemma',
      external: true,
      cta: false,
    ),
    (
      text: 'pub.dev',
      href: 'https://pub.dev/packages/flutter_gemma',
      external: true,
      cta: true,
    ),
  ];

  @override
  Component build(BuildContext context) {
    return nav(classes: 'navbar', [
      div(classes: 'navbar-inner', [
        a(href: '/', classes: 'navbar-brand', [
          img(
            src: '/images/logo-gemma.png',
            alt: 'flutter_gemma logo',
            classes: 'navbar-logo',
          ),
          span(classes: 'navbar-wordmark', [Component.text('flutter_gemma')]),
        ]),
        // Hamburger button (shown only on narrow screens via CSS).
        button(
          classes: 'navbar-burger',
          attributes: {
            'aria-label': 'Toggle navigation menu',
            'aria-expanded': _open ? 'true' : 'false',
          },
          onClick: () => setState(() => _open = !_open),
          [
            span(classes: 'navbar-burger-bar', []),
            span(classes: 'navbar-burger-bar', []),
            span(classes: 'navbar-burger-bar', []),
          ],
        ),
        div(classes: _open ? 'navbar-links is-open' : 'navbar-links', [
          for (final l in _links)
            // NO onClick here: this is a static multi-page site, so each link is
            // a full-page navigation via `href`. Attaching an onClick to a
            // @client <a> intercepts and SUPPRESSES the native navigation
            // (reported: clicking "Docs" did nothing). The mobile menu closes on
            // its own because navigation reloads the page (resets _open=false).
            a(
              href: l.href,
              classes: l.cta ? 'navbar-link navbar-link--cta' : 'navbar-link',
              attributes: l.external ? {'target': '_blank', 'rel': 'noopener'} : const {},
              [Component.text(l.text)],
            ),
        ]),
      ]),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    css('.navbar').styles(
      position: Position.sticky(top: 0.px),
      zIndex: ZIndex(100),
      width: 100.percent,
      backgroundColor: Brand.navy,
      radius: BorderRadius.circular(0.px),
      border: Border.only(
        bottom: BorderSide(color: Color('rgba(255,255,255,0.08)'), width: 1.px),
      ),
    ),
    css('.navbar-inner').styles(
      position: Position.relative(),
      display: Display.flex,
      flexDirection: FlexDirection.row,
      alignItems: AlignItems.center,
      justifyContent: JustifyContent.spaceBetween,
      maxWidth: 1200.px,
      margin: Margin.symmetric(horizontal: Unit.auto),
      padding: Padding.symmetric(horizontal: 2.rem, vertical: 1.rem),
    ),
    css('.navbar-brand').styles(
      display: Display.flex,
      flexDirection: FlexDirection.row,
      alignItems: AlignItems.center,
      gap: Gap.all(0.6.rem),
      textDecoration: TextDecoration.none,
    ),
    // Scoped under `.landing-root` ON PURPOSE: the landing reset
    // `.landing-root img { height: auto; max-width: 100% }` (landing_page.dart)
    // is specificity (0,1,1) and OUTRANKS a bare `.navbar-logo` (0,1,0),
    // silently overriding `height: 2.2rem` with `height: auto` — so the logo
    // rendered at its full intrinsic size, a giant logo filling the header.
    // `.landing-root .navbar-logo` is (0,2,0), which wins and restores 2.2rem.
    css('.landing-root .navbar-logo').styles(
      height: 2.2.rem,
      width: Unit.auto,
      display: Display.block,
    ),
    css('.navbar-wordmark').styles(
      fontFamily: Brand.fontSans,
      fontSize: 1.2.rem,
      fontWeight: FontWeight.w700,
      color: Brand.white,
      textDecoration: TextDecoration.none,
      letterSpacing: (-0.01).em,
    ),
    css('.navbar-link').styles(
      color: Brand.white70,
      textDecoration: TextDecoration.none,
      fontSize: 0.95.rem,
      fontWeight: FontWeight.w500,
      fontFamily: Brand.fontSans,
    ),
    css('.navbar-link--cta').styles(
      color: Brand.blueLight,
      fontWeight: FontWeight.w600,
    ),
    css('.navbar-link:hover').styles(color: Brand.white),
    css('.navbar-burger-bar').styles(
      display: Display.block,
      width: 100.percent,
      height: 2.px,
      backgroundColor: Brand.white,
      radius: BorderRadius.circular(2.px),
    ),
    // ---- MOBILE-FIRST BASE (narrow screens) ----
    // Burger visible, links collapse into an absolutely-positioned dropdown
    // that is hidden until `.is-open` is toggled. Desktop overrides below via a
    // min-width media query, so source order can't accidentally re-hide the
    // burger (the earlier ordering bug).
    css('.navbar-burger').styles(
      display: Display.flex,
      flexDirection: FlexDirection.column,
      justifyContent: JustifyContent.center,
      gap: Gap.all(5.px),
      width: 2.5.rem,
      height: 2.5.rem,
      padding: Padding.all(0.5.rem),
      backgroundColor: Color('transparent'),
      border: Border.none,
      cursor: Cursor.pointer,
      raw: {'flex-shrink': '0'},
    ),
    css('.navbar-links').styles(
      position: Position.absolute(top: 100.percent, left: 0.px, right: 0.px),
      display: Display.none,
      flexDirection: FlexDirection.column,
      alignItems: AlignItems.stretch,
      gap: Gap.all(0.px),
      backgroundColor: Brand.navy,
      padding: Padding.symmetric(vertical: 0.5.rem),
      border: Border.only(
        bottom: BorderSide(color: Color('rgba(255,255,255,0.08)'), width: 1.px),
      ),
    ),
    css('.navbar-links.is-open').styles(display: Display.flex),
    css('.navbar-links .navbar-link').styles(
      padding: Padding.symmetric(vertical: 0.85.rem, horizontal: 2.rem),
      fontSize: 1.rem,
    ),
    // ---- DESKTOP OVERRIDE (>= 769px) ----
    StyleRule.media(
      query: MediaQuery.screen(minWidth: 769.px),
      styles: [
        css('.navbar-burger').styles(display: Display.none),
        css('.navbar-links').styles(
          position: Position.static,
          display: Display.flex,
          flexDirection: FlexDirection.row,
          alignItems: AlignItems.center,
          gap: Gap.all(1.8.rem),
          backgroundColor: Color('transparent'),
          padding: Padding.zero,
          border: Border.none,
        ),
        css('.navbar-links .navbar-link').styles(
          padding: Padding.zero,
          fontSize: 0.95.rem,
        ),
      ],
    ),
  ];
}
