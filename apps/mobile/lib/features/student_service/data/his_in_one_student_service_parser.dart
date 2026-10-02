// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../domain/student_service_overview.dart';

/// Pure parsing/classification for the "Studienservice" page
/// (`studyservice-flow`) — no network code, same split as
/// `HisInOneHtmlParser`/`HisInOneGradesGateway`.
///
/// The page is one JSF form (`studyserviceForm`) with five tabs; switching
/// tabs is a full, non-AJAX form POST that re-renders the whole page with a
/// fresh `_flowExecutionKey`. Every extraction here is by stable, named
/// anchors (a label's text, a header's text, an id SUFFIX) rather than by a
/// `j_id_*`-style generated id or by position — those regenerate per render
/// and carry no meaning across page loads.
abstract final class HisInOneStudentServiceParser {
  static const String _formId = 'studyserviceForm';

  /// Whether [html] is recognisably the Studienservice page at all — checked
  /// before any tab-specific extraction, the same discipline
  /// `HisInOneHtmlParser.readOverview` uses for the exam tree.
  static bool isStudyServicePage(String html) =>
      _form(html_parser.parse(html)) != null;

  static dom.Element? _form(dom.Document document) =>
      _elementById(document, _formId);

  /// A manual scan rather than [dom.Document.getElementById]/a CSS `#id`
  /// selector: JSF ids contain `:` (e.g. `studyserviceForm:report_TabBtn`),
  /// and `package:html`'s CSS engine parses a bare `:` in a selector as the
  /// start of a pseudo-class, throwing `UnimplementedError` rather than
  /// matching the id. Same workaround `HisInOneHtmlParser._elementById` uses
  /// for the exam tree.
  static dom.Element? _elementById(dom.Document document, String id) {
    final List<dom.Element> stack = <dom.Element>[...document.children];
    while (stack.isNotEmpty) {
      final dom.Element current = stack.removeLast();
      if (current.id == id) return current;
      stack.addAll(current.children);
    }
    return null;
  }

  /// A request that switches to another tab: every hidden field of the
  /// currently loaded form, plus the exact `name`/`value` of the tab button
  /// itself — read from the real page, never assumed. `null` when the form or
  /// the named button is not there in a submittable shape, which the caller
  /// surfaces as `portalStructureChanged` rather than guessing a request that
  /// cannot possibly land on the intended tab.
  static TabSwitchRequest? buildTabSwitchRequest(String html, String buttonId) {
    final dom.Document document = html_parser.parse(html);
    final dom.Element? form = _form(document);
    if (form == null) return null;
    final dom.Element? button = _elementById(document, buttonId);
    final String? buttonName = button?.attributes['name'];
    final String? buttonValue = button?.attributes['value'];
    if (button == null || buttonName == null || buttonValue == null) {
      return null;
    }
    final String? action = form.attributes['action'];
    if (action == null || action.isEmpty) return null;

    final Map<String, String> formData = <String, String>{};
    for (final dom.Element input in form.querySelectorAll(
      'input[type=hidden]',
    )) {
      final String? name = input.attributes['name'];
      if (name == null) continue;
      formData[name] = input.attributes['value'] ?? '';
    }
    formData[buttonName] = buttonValue;
    return TabSwitchRequest(action: action, formData: formData);
  }

  /// The stable portion of a JSF AJAX request: the current form action and
  /// every hidden field. The source component is intentionally supplied by
  /// the gateway via `javax.faces.source`; real HISinOne job buttons need not
  /// have an HTML `name`/`value`, so treating them like full-submit tab buttons
  /// incorrectly rejects the portal's actual markup.
  static TabSwitchRequest? buildAjaxFormRequest(String html) {
    final dom.Document document = html_parser.parse(html);
    final dom.Element? form = _form(document);
    final String? action = form?.attributes['action'];
    if (form == null || action == null || action.isEmpty) return null;

    final Map<String, String> formData = <String, String>{};
    for (final dom.Element input in form.querySelectorAll(
      'input[type=hidden]',
    )) {
      final String? name = input.attributes['name'];
      if (name == null) continue;
      formData[name] = input.attributes['value'] ?? '';
    }
    return TabSwitchRequest(action: action, formData: formData);
  }

  /// The "Personendaten" block present at the top of every tab. Label/value
  /// pairs are matched by the label's own text, never by position or by the
  /// enclosing `j_id_*` id, which regenerates every render.
  static List<PersonalDataField> readPersonalData(String html) {
    final dom.Document document = html_parser.parse(html);
    final List<PersonalDataField> fields = <PersonalDataField>[];
    for (final dom.Element line in document.querySelectorAll('.oneLine')) {
      final dom.Element? labelEl = line.querySelector('.labelWithBG');
      final dom.Element? valueEl = line.querySelector('.answer');
      if (labelEl == null || valueEl == null) continue;
      final String label = _normalized(labelEl.text);
      final String value = _normalized(valueEl.text);
      if (label.isEmpty) continue;
      fields.add(PersonalDataField(label: label, value: value));
    }
    return fields;
  }

  static String? hoererstatusOf(List<PersonalDataField> fields) {
    for (final PersonalDataField field in fields) {
      if (field.label.toLowerCase() == 'hörerstatus') return field.value;
    }
    return null;
  }

  /// The "Kontaktdaten" tab's address/mail/phone tiles. A tile with no
  /// filled-in container is a real empty state, not a parse failure — it
  /// yields an entry with empty [ContactTile.lines].
  static List<ContactTile> readContactTiles(String html) {
    final dom.Document document = html_parser.parse(html);
    final List<ContactTile> tiles = <ContactTile>[];
    for (final dom.Element tile in document.querySelectorAll(
      '.tile_fieldset',
    )) {
      final dom.Element? heading = tile.querySelector('h2, h3');
      if (heading == null) continue;
      final List<String> lines = <String>[];
      for (final dom.Element container in tile.querySelectorAll(
        '.postaddressDataContainer.tileDataContainer, '
        '.emailDataContainer.tileDataContainer, '
        '.phoneDataContainer',
      )) {
        final String text = _normalized(container.text);
        if (text.isNotEmpty) lines.add(text);
      }
      tiles.add(ContactTile(heading: _normalized(heading.text), lines: lines));
    }
    return tiles;
  }

  /// "Meine Studiengänge": one row per programme, matched by the required
  /// header texts (never a fixed column count) before any row is read.
  static List<ProgrammeEntry>? readProgrammes(String html) {
    final dom.Document document = html_parser.parse(html);
    for (final dom.Element table in document.querySelectorAll(
      'table.tableWithSelect',
    )) {
      final List<String> headers = table
          .querySelectorAll('th.tableHeader')
          .map((dom.Element th) => _normalized(th.text))
          .toList(growable: false);
      if (!_hasRequiredProgrammeHeaders(headers)) continue;
      final Map<String, int> columnByHeader = <String, int>{
        for (int index = 0; index < headers.length; index++)
          headers[index].toLowerCase(): index,
      };
      final List<ProgrammeEntry> entries = <ProgrammeEntry>[];
      for (final dom.Element row in table.querySelectorAll(
        'tbody tr.listRowOdd, tbody tr.listRowEven',
      )) {
        final List<dom.Element> cells = row.querySelectorAll('td');
        final int maximumIndex = columnByHeader.values.reduce(
          (int a, int b) => a > b ? a : b,
        );
        if (cells.length <= maximumIndex) continue;
        entries.add(
          ProgrammeEntry(
            subject: _normalized(cells[columnByHeader['fach']!].text),
            subjectSemester: _normalized(
              cells[columnByHeader['fachsemester']!].text,
            ),
            subjectIndicator: _normalized(
              cells[columnByHeader['fachkennzeichen']!].text,
            ),
            examinationVersion: _normalized(
              cells[columnByHeader['prüfungsordnungsversion']!].text,
            ),
          ),
        );
      }
      return entries;
    }
    return null;
  }

  static bool _hasRequiredProgrammeHeaders(List<String> headers) {
    const List<String> required = <String>[
      'fach',
      'fachsemester',
      'fachkennzeichen',
      'prüfungsordnungsversion',
    ];
    final Set<String> lower = headers
        .map((String h) => h.toLowerCase())
        .toSet();
    return required.every(lower.contains);
  }

  /// "Bescheinigungen": every certificate type offered, with the exact
  /// button id to submit to generate it. Never the generated document.
  static List<CertificateOffer> readCertificateOffers(String html) {
    final dom.Document document = html_parser.parse(html);
    final List<CertificateOffer> offers = <CertificateOffer>[];
    for (final dom.Element item in document.querySelectorAll(
      'li.job-configuration-buttons-item.job',
    )) {
      final dom.Element? button = item.querySelector('button[type=submit]');
      final dom.Element? name = item.querySelector('.jobname');
      final String? id = button?.id;
      if (button == null || name == null || id == null || id.isEmpty) {
        continue;
      }
      offers.add(
        CertificateOffer(name: _normalized(name.text), jobButtonId: id),
      );
    }
    return offers;
  }

  /// Distinguishes a valid empty certificate section from a response that no
  /// longer contains the expected tab at all.
  static bool hasCertificateSection(String html) {
    final dom.Document document = html_parser.parse(html);
    return document
        .querySelectorAll('.groupname')
        .any(
          (dom.Element heading) =>
              _normalized(heading.text).toLowerCase().contains('bescheinigung'),
        );
  }

  /// "Zahlungen": the portal has no dedicated re-registration status field,
  /// only this indirect hint. Checked for the exact empty-state text first;
  /// a table row count is the only other recognised shape.
  static PaymentHint readPaymentHint(String html) {
    final dom.Document document = html_parser.parse(html);
    final bool hasEmptyNotice = document
        .querySelectorAll('*')
        .any(
          (dom.Element el) =>
              el.nodes.length == 1 &&
              _normalized(
                el.text,
              ).toLowerCase().contains('sie haben keine offenen zahlungen'),
        );
    if (hasEmptyNotice) {
      return const PaymentHint(kind: PaymentHintKind.noneOpen);
    }
    final dom.Element? table = _elementById(
      document,
      'studyserviceForm:billsAndPayment:fieldSetInvoicePaid:'
      'dataTableSalesInvoicesOffenTable',
    );
    if (table != null) {
      final int rows = table
          .querySelectorAll('tbody tr.listRowOdd, tbody tr.listRowEven')
          .length;
      return PaymentHint(kind: PaymentHintKind.open, openItemCount: rows);
    }
    return const PaymentHint(kind: PaymentHintKind.unrecognised);
  }

  /// The PrimeFaces `<p:poll>` component's own client id, read from
  /// `data-poll-button-client-id` on the `.polling-data-holder` span the
  /// started job renders. `null` when that marker is not there — the caller
  /// treats that as the job having no recognised polling mechanism.
  ///
  /// Reads from [cdataContentOf], not [html] directly: a JSF partial-response
  /// wraps its rendered markup in `<![CDATA[…]]>`, and an HTML5 tokenizer
  /// treats `<![CDATA[` as a "bogus comment" that swallows everything up to
  /// the very next `>` — which is the first real tag's own closing bracket.
  /// Parsing the XML envelope directly as HTML would silently lose that tag.
  static String? readPollButtonId(String partialResponseXml) {
    final dom.Element? holder = html_parser
        .parse(cdataContentOf(partialResponseXml))
        .querySelector('.polling-data-holder');
    final String? id = holder?.attributes['data-poll-button-client-id'];
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Concatenates every `<![CDATA[ … ]]>` payload of a JSF partial-response,
  /// so the real rendered HTML inside can be parsed on its own, without the
  /// XML envelope confusing an HTML5 tokenizer (see [readPollButtonId]).
  /// Returns the input unchanged when no CDATA section is found — a plain
  /// HTML page (not a partial-response) parses the same way either way.
  static String cdataContentOf(String xmlOrHtml) {
    final Iterable<RegExpMatch> matches = _cdataPattern.allMatches(xmlOrHtml);
    if (matches.isEmpty) return xmlOrHtml;
    return matches.map((RegExpMatch m) => m.group(1) ?? '').join('\n');
  }

  static final RegExp _cdataPattern = RegExp(
    r'<!\[CDATA\[(.*?)\]\]>',
    dotAll: true,
  );

  /// A JSF partial response can rotate the view state after every AJAX call.
  /// Keeping that value for the next poll avoids replaying a stale CSRF/view
  /// token while still refusing to synthesize one when the portal omits it.
  static String? viewStateFromPartialResponse(String xml) {
    final RegExpMatch? match = _viewStatePattern.firstMatch(xml);
    final String? value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static final RegExp _viewStatePattern = RegExp(
    r'''<update\s+id=["']javax\.faces\.ViewState[^"']*["']>\s*(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?\s*</update>''',
    dotAll: true,
  );

  /// Extracts the one-time document-download URL from a JSF/MyFaces
  /// partial-response, per the standard protocol: either an `<eval>` block
  /// whose script assigns `window.location`/navigates to a URL, or an
  /// `<update>` block whose rendered HTML contains a matching link. Returns
  /// `null` when neither shape is found — the caller surfaces that as
  /// `portalStructureChanged` rather than guessing at an undocumented AJAX
  /// contract.
  static String? extractDownloadUrlFromPartialResponse(String xml) =>
      _downloadUrlPattern.firstMatch(xml)?.group(0);

  static final RegExp _downloadUrlPattern = RegExp(
    r'''https?://[^\s"'<>\\]+state=docdownload[^\s"'<>\\]*''',
  );

  static String _normalized(String value) =>
      value.replaceAll(_whitespacePattern, ' ').trim();

  static final RegExp _whitespacePattern = RegExp(r'\s+');
}

/// A tab switch, ready to POST: every hidden field of the currently loaded
/// form, plus the clicked tab button's own `name`/`value`.
class TabSwitchRequest {
  const TabSwitchRequest({required this.action, required this.formData});

  final String action;
  final Map<String, String> formData;
}
