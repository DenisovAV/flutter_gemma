import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'sections/cta_section.dart';
import 'sections/examples.dart';
import 'sections/features.dart';
import 'sections/hero.dart';
import 'sections/models_gallery.dart';
import 'sections/nav_bar.dart';
import 'sections/platform_matrix.dart';
import 'sections/quick_start.dart';
import 'sections/site_footer.dart';
import 'sections/trust_bar.dart';
import 'sections/why_on_device.dart';
import '../theme/brand.dart';

/// The hand-built marketing landing page served at `/`.
///
/// Sections are composed here; each lives in its own file under
/// `lib/landing/sections/` so they can be edited independently.
class LandingPage extends StatelessComponent {
  const LandingPage({super.key});

  @override
  Component build(BuildContext context) {
    // Title / meta / charset for `/` are provided by the full `Document`
    // wrapper in `main.server.dart`'s route (charset defaults to utf-8 there).
    return main_(classes: 'landing-root', [
      const NavBar(),
      const Hero(),
      const TrustBar(),
      const Features(),
      const Examples(),
      const PlatformMatrix(),
      const QuickStart(),
      const ModelsGallery(),
      const WhyOnDevice(),
      const CtaSection(),
      const SiteFooter(),
    ]);
  }

  @css
  static List<StyleRule> get styles => [
    // Global resets and base
    css('*, *::before, *::after').styles(
      boxSizing: BoxSizing.borderBox,
    ),
    // NOTE: do NOT set background-color/color on `body` here — this @css is
    // bundled onto every page (incl. docs), and a global body-navy leaked under
    // the docs' light-mode dark text, making docs unreadable. Page background +
    // text colors live on `.landing-root` (here) and the docs ContentTheme.
    css('body').styles(
      margin: Margin.zero,
      padding: Padding.zero,
      fontFamily: Brand.fontSans,
    ),
    css('.landing-root').styles(
      display: Display.block,
      minHeight: 100.vh,
      backgroundColor: Brand.navy,
      color: Brand.white,
    ),
    // Shared section-title used by multiple sections
    css('.section-title').styles(
      fontFamily: Brand.fontSans,
      fontSize: 2.rem,
      fontWeight: FontWeight.w700,
      color: Brand.white,
      textAlign: TextAlign.center,
      margin: Margin.only(bottom: 1.rem, top: 0.px),
    ),
    // Shared btn styles (primary/outline defined per-section but base here)
    css('img').styles(
      maxWidth: 100.percent,
      height: Unit.auto,
      display: Display.block,
    ),
    css('h1, h2, h3, h4').styles(
      margin: Margin.zero,
      padding: Padding.zero,
    ),
    css('ul').styles(
      margin: Margin.zero,
      padding: Padding.zero,
    ),
  ];
}
