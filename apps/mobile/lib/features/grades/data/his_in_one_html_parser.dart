// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart' show compute;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../domain/decimal_parsing.dart';
import '../domain/exam_report.dart';
import '../domain/grade.dart';
import '../domain/grade_failure.dart';
import 'qis_html_parser.dart';

/// The id of the JSF section ("Leistungsdaten") that holds the exam-tree
/// table. A second, structurally identical table ("Studienverlauf") lives in
/// the sibling section `examsReadonly:degreeProgramProgressForReportAsTree`
/// and MUST NOT be matched — pinning to this section is what tells them apart.
///
/// Matched as a PREFIX, not as an exact id: the portal versions differ in how
/// deeply the table is nested below this section (older builds render it in
/// `…:tree:ExamOverviewForPersonTreeReadonly`, the build currently deployed at
/// Hochschule Anhalt does not use that inner id at all). Matching the section
/// and searching inside it covers both without pinning a version-specific id.
const String _examSectionIdPrefix = 'examsReadonly:overviewAsTreeReadonly';

/// What the exam-overview page actually is.
enum HisInOneOverviewKind {
  /// No `examsReadonly` form and no "Leistungsdaten" section — this is not the
  /// exam overview at all, so the portal structure is unknown.
  unrecognised,

  /// The "Leistungsdaten" section is there but holds no exam tree. The portal
  /// says "Es wurden keine Datensätze gefunden": the account is valid, it just
  /// has no exam results on THIS portal. An empty report, never an error.
  empty,

  /// A collapsed tree plus an "expand all" control — expand, then parse.
  expandable,

  /// A tree without any "expand all" control (the build currently deployed at
  /// Hochschule Anhalt has none; nodes are toggled individually). Parse the
  /// page as rendered instead of failing.
  rendered,
}

/// The classification of an exam-overview page, plus the expand request when
/// [kind] is [HisInOneOverviewKind.expandable].
class HisInOneOverview {
  const HisInOneOverview(this.kind, [this.expandRequest]);

  final HisInOneOverviewKind kind;
  final HisInOneExpandRequest? expandRequest;

  @override
  String toString() => 'HisInOneOverview(${kind.name})';
}

/// Everything needed to POST the "expand all" request for the collapsed exam
/// tree: the form's own `action`, every hidden field found on the page
/// (including `authenticity_token`, `javax.faces.ViewState` and
/// `examsReadonly_SUBMIT` — never hard-coded), and the button field to submit.
class HisInOneExpandRequest {
  const HisInOneExpandRequest({
    required this.action,
    required this.hiddenFields,
    required this.buttonName,
  });

  final String action;
  final Map<String, String> hiddenFields;
  final String buttonName;

  /// The full form-urlencoded body: every hidden field plus the button.
  Map<String, String> get formData => <String, String>{
    ...hiddenFields,
    buttonName: '',
  };
}

/// A full, non-AJAX form submission ready to POST: an `action` plus a
/// complete `formData` body (hidden fields, the chosen button's own
/// name/value, and any extra marker field such as `DISABLE_VALIDATION`).
/// Unlike [HisInOneExpandRequest], the button value here is never an empty
/// string — the real printable-report buttons submit their own label text.
class HisInOneFullPostRequest {
  const HisInOneFullPostRequest({required this.action, required this.formData});

  final String action;
  final Map<String, String> formData;
}

/// Parses HISinOne (JSF-MyFaces) HTML into domain objects using a real DOM
/// parser (no regex over general HTML).
///
/// The exam tree table is found by [_treeContainerId] and its
/// `treeTableWithIcons` class, never by table order alone (a second, decoy
/// table with the same layout exists on the page). Columns are mapped
/// EXCLUSIVELY by header text, never by fixed indices, because the visible
/// column set is configurable per account. If the required columns (Titel,
/// Bewertung, Status) or the table itself are not found, this reports
/// [GradeFailureKind.portalStructureChanged] and NEVER returns a partial tree.
///
/// [findExpandRequest] and [parseGradeReport] both call `html.parse` on
/// potentially large pages; that call and the pure-data extraction that
/// follows it run on a background isolate via [compute] instead of the UI
/// isolate. Each delegates to a private `_...Sync` static method that does
/// the actual, synchronous work — that private method is what runs on the
/// background isolate.
abstract final class HisInOneHtmlParser {
  static const Set<String> _requiredHeaders = <String>{'bewertung', 'status'};

  /// True when the page still shows the login form (fields `asdf` / `fdsa`).
  /// Identical login form to the legacy portal, so the same detector applies.
  ///
  /// NOT usable on its own to detect a FAILED login on HISinOne: unlike the
  /// legacy portal, HISinOne renders a hidden `id="sessionTimeoutLoginForm"`
  /// with the very same `asdf`/`fdsa` fields on every page — logged in or
  /// not — for re-authentication after a session timeout. So this is always
  /// `true` here. Use [isAuthenticated] to decide login success instead.
  static Future<bool> hasLoginForm(String htmlSource) =>
      QisHtmlParser.hasLoginForm(htmlSource);

  /// True when the page is authenticated — a logout link
  /// (`category=auth.logout`) is present. This is the POSITIVE check the
  /// HISinOne gateway must use after login: the negative `hasLoginForm` check
  /// is worthless here (see its doc comment) and previously made every login
  /// — including correct credentials — fail.
  static Future<bool> isAuthenticated(String htmlSource) =>
      QisHtmlParser.isAuthenticated(htmlSource);

  /// Builds the "expand all" request from the collapsed exam-overview page:
  /// the `action` of the `id="examsReadonly"` form, ALL of its hidden fields
  /// (the dynamic `_flowExecutionKey`, `authenticity_token` and
  /// `javax.faces.ViewState` among them), and the expand-all button — found by
  /// its id SUFFIX `:expandAll2`, falling back to `:expandAll`, never by its
  /// (localized) label. Returns `null` when the form or a button cannot be
  /// found, so the caller can report `portalStructureChanged`.
  static Future<HisInOneExpandRequest?> findExpandRequest(String htmlSource) =>
      compute(_findExpandRequestSync, htmlSource);

  /// Classifies the exam-overview page so the gateway can tell an account
  /// WITHOUT exam results on this portal (`empty`) apart from a page it does
  /// not recognise (`unrecognised`).
  ///
  /// Before this existed, both looked identical — no "expand all" button — and
  /// an empty Leistungsdaten section was reported as
  /// [GradeFailureKind.portalStructureChanged], which aborted setup before the
  /// other portal was ever tried.
  static Future<HisInOneOverview> readOverview(String htmlSource) =>
      compute(_readOverviewSync, htmlSource);

  static HisInOneOverview _readOverviewSync(String htmlSource) {
    final Document doc = html.parse(htmlSource);
    final Element? form = _elementById(doc, 'examsReadonly');
    final Element? section = _findExamSection(doc);
    if (form == null && section == null) {
      return const HisInOneOverview(HisInOneOverviewKind.unrecognised);
    }
    final HisInOneExpandRequest? expand = form == null
        ? null
        : _expandRequestOf(form);
    if (expand != null) {
      return HisInOneOverview(HisInOneOverviewKind.expandable, expand);
    }
    if (_findExamTreeTable(doc) != null) {
      return const HisInOneOverview(HisInOneOverviewKind.rendered);
    }
    if (section != null) {
      return const HisInOneOverview(HisInOneOverviewKind.empty);
    }
    return const HisInOneOverview(HisInOneOverviewKind.unrecognised);
  }

  static HisInOneExpandRequest? _findExpandRequestSync(String htmlSource) {
    final Document doc = html.parse(htmlSource);
    final Element? form = _elementById(doc, 'examsReadonly');
    if (form == null) return null;
    return _expandRequestOf(form);
  }

  static HisInOneExpandRequest? _expandRequestOf(Element form) {
    final String? action = form.attributes['action'];
    if (action == null || action.isEmpty) return null;

    final Map<String, String> hidden = <String, String>{};
    for (final Element input in form.querySelectorAll('input[type="hidden"]')) {
      final String? name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      hidden[name] = input.attributes['value'] ?? '';
    }

    final String? buttonName =
        _buttonBySuffix(form, ':expandAll2') ??
        _buttonBySuffix(form, ':expandAll');
    if (buttonName == null) return null;

    return HisInOneExpandRequest(
      action: action,
      hiddenFields: hidden,
      buttonName: buttonName,
    );
  }

  static String? _buttonBySuffix(Element form, String suffix) {
    for (final Element el in form.querySelectorAll(
      'input[type="submit"], button',
    )) {
      final String id = el.attributes['id'] ?? '';
      if (id.endsWith(suffix)) return el.attributes['name'] ?? id;
    }
    return null;
  }

  /// Reads the exam-overview page's own fixed "Bescheinigungen" print
  /// buttons, found by their stable `submit_print_pdf` class — confirmed
  /// 2026-10-04 from the real page, never assumed to exist. An account or
  /// portal build without this section yields an empty list, not an error:
  /// it is a legitimate absence, exactly like [HisInOneOverviewKind.empty]
  /// for the exam tree itself.
  static Future<List<ExamReportOffer>> findExamReports(String htmlSource) =>
      compute(_findExamReportsSync, htmlSource);

  static List<ExamReportOffer> _findExamReportsSync(String htmlSource) {
    final Document doc = html.parse(htmlSource);
    final List<ExamReportOffer> offers = <ExamReportOffer>[];
    for (final Element button in doc.querySelectorAll(
      'button.submit_print_pdf',
    )) {
      final String? id = button.attributes['id'];
      final String? label = button.attributes['value'];
      if (id == null || id.isEmpty || label == null || label.isEmpty) {
        continue;
      }
      offers.add(ExamReportOffer(buttonId: id, label: label));
    }
    return offers;
  }

  /// Builds the full, non-AJAX form submission for one chosen
  /// [ExamReportOffer]: the `examsReadonly` form's own `action`, every
  /// hidden field already on the page, the button's own name/value (read
  /// fresh, never cached across page loads) and `DISABLE_VALIDATION=true` —
  /// exactly what the real button's own `myfaces.oam.submitForm` call sends
  /// (confirmed 2026-10-04). `null` when the form or the named button is not
  /// there, so the caller reports `portalStructureChanged` rather than
  /// guessing a request that cannot possibly land on the right report.
  static Future<HisInOneFullPostRequest?> buildExamReportPostRequest(
    String htmlSource,
    String buttonId,
  ) => compute(_buildExamReportPostRequestSync, (htmlSource, buttonId));

  static HisInOneFullPostRequest? _buildExamReportPostRequestSync(
    (String, String) args,
  ) {
    final (String htmlSource, String buttonId) = args;
    final Document doc = html.parse(htmlSource);
    final Element? form = _elementById(doc, 'examsReadonly');
    if (form == null) return null;
    final String? action = form.attributes['action'];
    if (action == null || action.isEmpty) return null;
    final Element? button = _elementById(doc, buttonId);
    final String? buttonValue = button?.attributes['value'];
    if (button == null || buttonValue == null) return null;

    final Map<String, String> formData = <String, String>{};
    for (final Element input in form.querySelectorAll('input[type="hidden"]')) {
      final String? name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      formData[name] = input.attributes['value'] ?? '';
    }
    formData[buttonId] = buttonValue;
    formData['DISABLE_VALIDATION'] = 'true';
    return HisInOneFullPostRequest(action: action, formData: formData);
  }

  /// Parses the expanded exam-tree page. Leaf rows (real exam results) only —
  /// a row is a leaf when no OTHER row's path starts with `<path>.`, decided
  /// structurally from the `Ebene` path column, never from a CSS class, icon
  /// or number pattern. Each leaf carries its parent node's title as
  /// [GradeEntry.module].
  static Future<GradeReport> parseGradeReport(String htmlSource) =>
      compute(_parseGradeReportSync, htmlSource);

  static GradeReport _parseGradeReportSync(String htmlSource) {
    final Document doc = html.parse(htmlSource);
    final Element? table = _findExamTreeTable(doc);
    if (table == null) {
      throw const GradeFailure(GradeFailureKind.portalStructureChanged);
    }

    final List<Element> rows = table.querySelectorAll('tr');
    Element? headerRow;
    for (final Element row in rows) {
      if (row.querySelector('th') != null) {
        headerRow = row;
        break;
      }
    }
    if (headerRow == null) {
      throw const GradeFailure(GradeFailureKind.portalStructureChanged);
    }

    final List<Element> headerCells = headerRow.querySelectorAll('th');
    int titleHeaderIndex = -1;
    int titleColspan = 1;
    for (int i = 0; i < headerCells.length; i++) {
      final int cs = _colspan(headerCells[i]);
      if (cs > 1) {
        titleHeaderIndex = i;
        titleColspan = cs;
        break;
      }
    }
    if (titleHeaderIndex == -1) {
      throw const GradeFailure(GradeFailureKind.portalStructureChanged);
    }

    // The header texts for every field column AFTER Titel, in document order —
    // this order is what data-row cells after the title cell map to 1:1.
    final List<String> fieldHeaders = headerCells
        .sublist(titleHeaderIndex + 1)
        .map((Element e) => _norm(e.text))
        .toList();
    final Set<String> lowerHeaders = fieldHeaders
        .map((String h) => h.toLowerCase())
        .toSet();
    if (!_requiredHeaders.every(lowerHeaders.contains)) {
      throw const GradeFailure(GradeFailureKind.portalStructureChanged);
    }

    final List<_RawRow> raw = <_RawRow>[];
    for (final Element row in rows) {
      if (row.querySelector('th') != null) continue; // header row
      final List<Element> cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;
      final String path = _norm(cells[0].text);
      if (path.isEmpty) continue; // spacer row

      int cumulative = 0;
      int titleCellIndex = -1;
      for (int i = 1; i < cells.length; i++) {
        cumulative += _colspan(cells[i]);
        if (cumulative >= titleColspan) {
          titleCellIndex = i;
          break;
        }
      }
      if (titleCellIndex == -1) continue; // malformed row, cannot locate title

      final String title = _norm(cells[titleCellIndex].text);
      final Map<String, String> fields = <String, String>{};
      for (int j = 0; j < fieldHeaders.length; j++) {
        final int dataIndex = titleCellIndex + 1 + j;
        fields[fieldHeaders[j].toLowerCase()] = dataIndex < cells.length
            ? _norm(cells[dataIndex].text)
            : '';
      }
      raw.add(
        _RawRow(
          path: path,
          title: title,
          fields: fields,
          headerLabels: fieldHeaders,
        ),
      );
    }

    final Set<String> paths = raw.map((_RawRow r) => r.path).toSet();
    final Set<String> nonLeafPaths = <String>{};
    for (final String p in paths) {
      int dotIndex = p.lastIndexOf('.');
      while (dotIndex > 0) {
        nonLeafPaths.add(p.substring(0, dotIndex));
        dotIndex = p.lastIndexOf('.', dotIndex - 1);
      }
    }
    bool isLeaf(String path) => !nonLeafPaths.contains(path);
    final Map<String, String> titleByPath = <String, String>{
      for (final _RawRow r in raw) r.path: r.title,
    };

    final List<GradeEntry> entries = <GradeEntry>[];
    for (final _RawRow r in raw) {
      // Every row is kept — including intermediate tree/module nodes and the
      // (itself non-leaf) `C-Sammelkonto` average row. A leaf filter here
      // would silently drop the average from the report before
      // `GradeProjection` ever sees it. `isLeaf` is carried as a field so the
      // presentation layer decides what to display, never the parser.
      final List<String> segments = r.path.split('.');
      final String? module = segments.length > 1
          ? titleByPath[segments.sublist(0, segments.length - 1).join('.')]
          : null;

      final String statusText = r.field('status');
      final ExamStatus status = _parseStatusCode(statusText);
      final Map<String, String> extras = <String, String>{
        for (final String header in r.headerLabels)
          if (!_mappedHeaders.contains(header.toLowerCase()) &&
              (r.field(header.toLowerCase())).isNotEmpty)
            header: r.field(header.toLowerCase()),
      };

      entries.add(
        GradeEntry(
          examNumber: r.field('nummer'),
          title: r.title,
          grade: _parseGrade(r.field('bewertung'), status),
          status: status,
          statusText: statusText,
          bonus: _optional(r.field('bonus')),
          attempt: _optional(r.field('versuch')),
          examDate: _parseDateTime(r.field('freigabedatum')),
          examiner: null,
          path: r.path,
          module: module,
          extras: extras,
          isLeaf: isLeaf(r.path),
        ),
      );
    }
    return GradeReport(entries);
  }

  // Headers that are mapped onto a dedicated GradeEntry field rather than
  // ending up in `extras`.
  static const Set<String> _mappedHeaders = <String>{
    'nummer',
    'bewertung',
    'status',
    'versuch',
    'freigabedatum',
    'bonus',
  };

  static String? _optional(String v) => v.isEmpty ? null : v;

  static int _colspan(Element e) =>
      int.tryParse(e.attributes['colspan'] ?? '1') ?? 1;

  static Grade _parseGrade(String raw, ExamStatus status) {
    final double? numeric = parseGradeDecimal(raw);
    if (numeric != null && numeric > 0) return Grade.graded(numeric);
    if (status == ExamStatus.passed) return const Grade.passedUngraded();
    return const Grade.none();
  }

  static ExamStatus _parseStatusCode(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'BE':
        return ExamStatus.passed;
      case 'NB':
        return ExamStatus.failed;
      case 'PV':
        return ExamStatus.present;
      default:
        return ExamStatus.unknown;
    }
  }

  static final RegExp _dateTimePattern = RegExp(
    r'^(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2}):(\d{2})$',
  );

  static DateTime? _parseDateTime(String raw) {
    final RegExpMatch? m = _dateTimePattern.firstMatch(raw.trim());
    if (m == null) return null;
    final int day = int.parse(m.group(1)!);
    final int month = int.parse(m.group(2)!);
    final int year = int.parse(m.group(3)!);
    final int hour = int.parse(m.group(4)!);
    final int minute = int.parse(m.group(5)!);
    final int second = int.parse(m.group(6)!);
    final DateTime dt = DateTime(year, month, day, hour, minute, second);
    if (dt.day != day || dt.month != month) return null;
    return dt;
  }

  static final RegExp _whitespacePattern = RegExp(r'\s+');

  static String _norm(String raw) =>
      raw.replaceAll(' ', ' ').replaceAll(_whitespacePattern, ' ').trim();

  /// The "Leistungsdaten" section element, matched by [_examSectionIdPrefix]
  /// (exact id or `<prefix>:` descendant id), or `null` when the page has no
  /// such section.
  static Element? _findExamSection(Document doc) =>
      _firstElementWhere(doc, _isExamSectionId);

  /// The exam tree table — the first `table.treeTableWithIcons` inside the
  /// "Leistungsdaten" section. The Studienverlauf tree lives under a different
  /// section id and is therefore never matched.
  static Element? _findExamTreeTable(Document doc) {
    final List<Element> stack = <Element>[...doc.children];
    while (stack.isNotEmpty) {
      final Element current = stack.removeLast();
      if (_isExamSectionId(current.id)) {
        final Element? table = current.querySelector(
          'table.treeTableWithIcons',
        );
        if (table != null) return table;
      }
      stack.addAll(current.children);
    }
    return null;
  }

  static bool _isExamSectionId(String id) =>
      id == _examSectionIdPrefix || id.startsWith('$_examSectionIdPrefix:');

  static Element? _firstElementWhere(Document doc, bool Function(String) test) {
    final List<Element> stack = <Element>[...doc.children];
    while (stack.isNotEmpty) {
      final Element current = stack.removeLast();
      if (test(current.id)) return current;
      stack.addAll(current.children);
    }
    return null;
  }

  /// A manual `id` attribute scan — NOT a `#id` CSS selector, because JSF ids
  /// contain `:`, which `package:html`'s CSS engine misparses as a
  /// pseudo-class selector and throws on.
  static Element? _elementById(Document doc, String id) {
    final List<Element> stack = <Element>[...doc.children];
    while (stack.isNotEmpty) {
      final Element current = stack.removeLast();
      if (current.id == id) return current;
      stack.addAll(current.children);
    }
    return null;
  }
}

class _RawRow {
  const _RawRow({
    required this.path,
    required this.title,
    required this.fields,
    required this.headerLabels,
  });

  final String path;
  final String title;
  final Map<String, String> fields;
  final List<String> headerLabels;

  String field(String lowerHeader) => fields[lowerHeader] ?? '';
}
