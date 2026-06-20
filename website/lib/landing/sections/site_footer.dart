import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../theme/brand.dart';

/// Site footer with link columns and copyright.
class SiteFooter extends StatelessComponent {
  const SiteFooter({super.key});

  @override
  Component build(BuildContext context) {
    return footer(
      classes: 'site-footer',
      [
        div(classes: 'footer-inner', [
          // Columns row
          div(classes: 'footer-cols', [
            // Packages column
            div(classes: 'footer-col', [
              h4(classes: 'footer-col-title', [Component.text('Packages')]),
              ul(classes: 'footer-links', [
                li([
                  a(
                    href: 'https://pub.dev/packages/flutter_gemma',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('flutter_gemma (core)')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://pub.dev/packages/flutter_gemma_litertlm',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('flutter_gemma_litertlm')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://pub.dev/packages/flutter_gemma_mediapipe',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('flutter_gemma_mediapipe')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://pub.dev/packages/flutter_gemma_embeddings',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('flutter_gemma_embeddings')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://pub.dev/packages/flutter_gemma_rag_qdrant',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('flutter_gemma_rag_qdrant')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://pub.dev/packages/flutter_gemma_rag_sqlite',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('flutter_gemma_rag_sqlite')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://pub.dev/packages/genkit_flutter_gemma',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('genkit_flutter_gemma')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://pub.dev/packages/genkit_hybrid',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('genkit_hybrid')],
                  ),
                ]),
              ]),
            ]),
            // Docs column
            div(classes: 'footer-col', [
              h4(classes: 'footer-col-title', [Component.text('Docs')]),
              ul(classes: 'footer-links', [
                li([
                  a(href: '/docs/getting-started', classes: 'footer-link', [Component.text('Getting Started')]),
                ]),
                li([
                  a(href: '/docs/installation', classes: 'footer-link', [Component.text('Installation')]),
                ]),
                li([
                  a(href: '/docs/models', classes: 'footer-link', [Component.text('Models')]),
                ]),
                li([
                  a(href: '/docs/multimodal', classes: 'footer-link', [Component.text('Multimodal')]),
                ]),
                li([
                  a(href: '/docs/function-calling', classes: 'footer-link', [Component.text('Function Calling')]),
                ]),
                li([
                  a(href: '/docs/embeddings-and-rag', classes: 'footer-link', [Component.text('Embeddings & RAG')]),
                ]),
                li([
                  a(href: '/docs/migration', classes: 'footer-link', [Component.text('Migration (0.x → 1.0)')]),
                ]),
              ]),
            ]),
            // Links column
            div(classes: 'footer-col', [
              h4(classes: 'footer-col-title', [Component.text('Links')]),
              ul(classes: 'footer-links', [
                li([
                  a(
                    href: 'https://sashadenisov.dev',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('Author')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://github.com/DenisovAV/flutter_gemma',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('GitHub')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://pub.dev/packages/flutter_gemma',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('pub.dev')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://medium.com/@denisov.shureg',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('Medium blog')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://deepwiki.com/DenisovAV/flutter_gemma',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('DeepWiki')],
                  ),
                ]),
                li([
                  a(
                    href: 'https://ko-fi.com/flutter_gemma',
                    classes: 'footer-link',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('Ko-fi')],
                  ),
                ]),
              ]),
            ]),
          ]),
          // Bottom bar
          div(classes: 'footer-bottom', [
            span(classes: 'footer-copy', [Component.text('MIT © Sasha Denisov')]),
            span(classes: 'footer-copy', [
              Component.text('Made with '),
              a(
                href: 'https://jaspr.dev',
                classes: 'footer-link',
                attributes: {'target': '_blank', 'rel': 'noopener'},
                [Component.text('Jaspr')],
              ),
            ]),
          ]),
        ]),
      ],
    );
  }

  @css
  static List<StyleRule> get styles => [
    css('.site-footer').styles(
      backgroundColor: Brand.navyDeep,
      radius: BorderRadius.circular(0.px),
      border: Border.only(
        top: BorderSide(color: Color('rgba(255,255,255,0.08)'), width: 1.px),
      ),
      padding: Padding.symmetric(vertical: 4.rem),
    ),
    css('.footer-inner').styles(
      maxWidth: 1200.px,
      margin: Margin.symmetric(horizontal: Unit.auto),
      padding: Padding.symmetric(horizontal: 2.rem),
      display: Display.flex,
      flexDirection: FlexDirection.column,
      gap: Gap.all(3.rem),
    ),
    css('.footer-cols').styles(
      display: Display.grid,
      gridTemplate: GridTemplate(
        columns: GridTracks([
          GridTrack.repeat(
            TrackRepeat.autoFit,
            [GridTrack(TrackSize.minmax(TrackSize(180.px), TrackSize.fr(1)))],
          ),
        ]),
      ),
      gap: Gap.all(2.5.rem),
    ),
    css('.footer-col-title').styles(
      fontFamily: Brand.fontSans,
      fontWeight: FontWeight.w600,
      fontSize: 0.875.rem,
      color: Brand.white,
      textTransform: TextTransform.upperCase,
      letterSpacing: 0.08.em,
      margin: Margin.only(bottom: 1.rem, top: 0.px),
    ),
    css('.footer-links').styles(
      listStyle: ListStyle.none,
      margin: Margin.zero,
      padding: Padding.zero,
      display: Display.flex,
      flexDirection: FlexDirection.column,
      gap: Gap.all(0.6.rem),
    ),
    css('.footer-link').styles(
      fontFamily: Brand.fontSans,
      fontSize: 0.875.rem,
      color: Brand.white70,
      textDecoration: TextDecoration.none,
    ),
    css('.footer-link:hover').styles(
      color: Brand.white,
      textDecoration: TextDecoration(line: TextDecorationLine.underline),
    ),
    css('.footer-bottom').styles(
      display: Display.flex,
      flexDirection: FlexDirection.row,
      justifyContent: JustifyContent.spaceBetween,
      flexWrap: FlexWrap.wrap,
      gap: Gap.all(0.75.rem),
      border: Border.only(
        top: BorderSide(color: Color('rgba(255,255,255,0.08)'), width: 1.px),
      ),
      padding: Padding.only(top: 1.5.rem),
    ),
    css('.footer-copy').styles(
      fontFamily: Brand.fontSans,
      fontSize: 0.825.rem,
      color: Brand.white50,
    ),
  ];
}
