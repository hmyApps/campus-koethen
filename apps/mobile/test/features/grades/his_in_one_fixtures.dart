// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer
//
// Anonymised HISinOne fixtures. NONE of these contain real names, matrikel
// numbers, examiners, exams or grades — every value is invented for testing.

/// A logged-out login page (fields `asdf` / `fdsa`) — the same login form as
/// the legacy portal.
const String hisInOneLoginFormHtml = '''
<html><head><title>Anmeldung</title></head><body>
  <form method="post"
        action="/qisserver/rds?state=user&type=1&category=auth.login">
    <input type="text" name="asdf" />
    <input type="password" name="fdsa" />
    <input type="submit" value="Anmelden" />
  </form>
</body></html>''';

/// The collapsed exam-overview page: the `examsReadonly` form with its hidden
/// fields (`authenticity_token`, `javax.faces.ViewState`,
/// `examsReadonly_SUBMIT`, and the dynamic `_flowExecutionKey`) and the
/// "expand all" button, found by its id SUFFIX, never its label.
const String hisInOneCollapsedOverviewHtml = '''
<html><head><title>Notenspiegel</title></head><body>
  <form id="examsReadonly" method="post" action="/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml">
    <input type="hidden" name="authenticity_token" value="TOKEN-XYZ" />
    <input type="hidden" name="javax.faces.ViewState" value="VIEWSTATE-1" />
    <input type="hidden" name="examsReadonly_SUBMIT" value="1" />
    <input type="hidden" name="_flowExecutionKey" value="e1s3" />
    <input type="submit" id="examsReadonly:overviewAsTreeReadonly:expandAll2" name="examsReadonly:overviewAsTreeReadonly:expandAll2" value="Alle aufklappen" />
  </form>
</body></html>''';

/// Same page, but only the OLDER `:expandAll` suffix is present — the fallback
/// path must be used.
const String hisInOneCollapsedOverviewFallbackButtonHtml = '''
<html><head><title>Notenspiegel</title></head><body>
  <form id="examsReadonly" method="post" action="/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml">
    <input type="hidden" name="authenticity_token" value="TOKEN-XYZ" />
    <input type="hidden" name="javax.faces.ViewState" value="VIEWSTATE-1" />
    <input type="submit" id="examsReadonly:overviewAsTreeReadonly:expandAll" name="examsReadonly:overviewAsTreeReadonly:expandAll" value="Expand all" />
  </form>
</body></html>''';

/// A page with no `examsReadonly` form at all (structure changed).
const String hisInOneNoFormHtml = '''
<html><head><title>Notenspiegel</title></head><body>
  <p>Keine Übersicht verfügbar.</p>
</body></html>''';

/// The "Bescheinigungen" section of the real exam-overview page (confirmed
/// 2026-10-04): three fixed print buttons, found by their stable
/// `submit_print_pdf` class, each a classic full form POST
/// (`myfaces.oam.submitForm`) rather than an AJAX request — no job, no
/// polling. Labels and ids are real portal chrome, not personal data.
const String hisInOneExamReportsHtml = '''
<html><head><title>Leistungen</title></head><body>
  <form id="examsReadonly" method="post" action="/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml?_flowId=examsOverviewForPerson-flow&_flowExecutionKey=e8s1">
    <input type="hidden" name="authenticity_token" value="TOKEN-XYZ" />
    <input type="hidden" name="javax.faces.ViewState" value="e8s1" />
    <div id="examsReadonly:exaReports:fieldset_exaReports">
      <h2>Bescheinigungen</h2>
      <ul class="buttons_vertical">
        <li><button id="examsReadonly:exaReports:fieldset_exaReports:printReport_0"
                    name="examsReadonly:exaReports:fieldset_exaReports:printReport_0"
                    type="submit"
                    value="Leistungsübersicht (bestandene Leistungen) / List of passed exam (german) [PDF]"
                    onclick="return myfaces.oam.submitForm('examsReadonly','examsReadonly:exaReports:fieldset_exaReports:printReport_0',null,[['DISABLE_VALIDATION','true']]);"
                    class="submit_print_pdf immediate">
          <span>Leistungsübersicht (bestandene Leistungen) / List of passed exam (german) [PDF]</span>
        </button></li>
        <li><button id="examsReadonly:exaReports:fieldset_exaReports:printReport_1"
                    name="examsReadonly:exaReports:fieldset_exaReports:printReport_1"
                    type="submit"
                    value="Leistungsübersicht bestandene Leistungen (englisch) / List of passed exams (english) [PDF]"
                    onclick="return myfaces.oam.submitForm('examsReadonly','examsReadonly:exaReports:fieldset_exaReports:printReport_1',null,[['DISABLE_VALIDATION','true']]);"
                    class="submit_print_pdf immediate">
          <span>Leistungsübersicht bestandene Leistungen (englisch) / List of passed exams (english) [PDF]</span>
        </button></li>
        <li><button id="examsReadonly:exaReports:fieldset_exaReports:printReport_2"
                    name="examsReadonly:exaReports:fieldset_exaReports:printReport_2"
                    type="submit"
                    value="Leistungsübersicht fehlende Leistungen / Overview of missing exam [PDF]"
                    onclick="return myfaces.oam.submitForm('examsReadonly','examsReadonly:exaReports:fieldset_exaReports:printReport_2',null,[['DISABLE_VALIDATION','true']]);"
                    class="submit_print_pdf immediate">
          <span>Leistungsübersicht fehlende Leistungen / Overview of missing exam [PDF]</span>
        </button></li>
      </ul>
    </div>
    <input type="hidden" name="examsReadonly_SUBMIT" value="1" />
  </form>
</body></html>''';

/// The exam-overview page with no "Bescheinigungen" section at all — a
/// legitimate state (not every account/portal build offers one), never a
/// structure-change error.
const String hisInOneNoExamReportsHtml = '''
<html><head><title>Leistungen</title></head><body>
  <form id="examsReadonly" method="post" action="/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml">
    <input type="hidden" name="authenticity_token" value="TOKEN-XYZ" />
    <input type="hidden" name="javax.faces.ViewState" value="e1s1" />
  </form>
</body></html>''';

/// An authenticated HISinOne page: a logout link (the actual login-success
/// signal), PLUS the hidden `sessionTimeoutLoginForm` that HISinOne renders
/// on every page, logged in or not, with the very same `asdf`/`fdsa` fields
/// as the real login form. A login check that merely tests for the login
/// form's absence sees this form and wrongly treats a successful login as
/// failed — this fixture is the regression case for that bug.
const String hisInOneAuthenticatedLandingHtml = '''
<html><head><title>Startseite</title></head><body>
  <a href="/qisserver/rds?state=user&type=3&category=auth.logout">Abmelden</a>
  <form id="sessionTimeoutLoginForm" method="post"
        action="/qisserver/rds?state=user&type=1&category=auth.login">
    <input type="text" name="asdf" />
    <input type="password" name="fdsa" />
  </form>
</body></html>''';

const String _headerRow =
    '<tr><th class="invisible">Ebene</th><th colspan="9">Titel</th>'
    '<th>Nummer</th><th>Versuch</th><th>Rücktritt</th><th>Bewertung</th>'
    '<th>Bonus</th><th>Malus</th><th>Status</th><th>Freiversuch</th>'
    '<th>Vermerk</th><th>Vorbehalt</th><th>Zusatzmerkmal</th>'
    '<th>Freigabedatum</th><th>Aktionen</th></tr>';

/// One data row. [depth] controls the indentation-cell count (`depth - 1`)
/// and the title cell's colspan (`10 - depth`), matching the real portal's
/// "cumulative colspan reaches the Titel header's colspan" layout.
String _row(
  String path,
  int depth,
  String title, {
  String nummer = '',
  String versuch = '',
  String ruecktritt = '',
  String bewertung = '',
  String bonus = '',
  String malus = '',
  String status = '',
  String freiversuch = '',
  String vermerk = '',
  String vorbehalt = '',
  String zusatzmerkmal = '',
  String freigabedatum = '',
  String aktionen = '',
}) {
  final String indent = '<td>&nbsp;</td>' * (depth - 1);
  final int titleColspan = 10 - depth;
  return '<tr><td class="invisible">$path</td>$indent'
      '<td colspan="$titleColspan">$title</td>'
      '<td>$nummer</td><td>$versuch</td><td>$ruecktritt</td>'
      '<td>$bewertung</td><td>$bonus</td><td>$malus</td><td>$status</td>'
      '<td>$freiversuch</td><td>$vermerk</td><td>$vorbehalt</td>'
      '<td>$zusatzmerkmal</td><td>$freigabedatum</td><td>$aktionen</td></tr>';
}

/// The Studienverlauf decoy table: same header/column layout as the exam tree,
/// under a DIFFERENT container id — it must never be matched.
const String _decoyStudienverlaufHtml =
    '''
<div id="studyProgress:overviewAsTreeReadonly:tree:StudyProgressTreeReadonly">
  <table class="treeTableWithIcons">
    $_headerRow
    <tr><td class="invisible">1</td><td colspan="9">Decoy-Wurzel</td>
      <td>DECOY</td><td></td><td></td><td>9,9</td><td></td><td></td><td>BE</td>
      <td></td><td></td><td></td><td></td><td></td><td></td></tr>
  </table>
</div>''';

/// The expanded exam tree (after the "expand all" POST). Two roots (multiple
/// Abschlüsse), a module with two leaves (a pass and a retake NB), an
/// unbenotet-bestanden leaf, a C-Sammelkonto average row that is itself an
/// INNER node (it has one child, "Prüfungsleistungen gesamt") — matching the
/// real portal, where the average row is not a leaf — and a second root with
/// an unknown status code.
final String hisInOneExpandedTreeHtml =
    '''
<html><head><title>Notenspiegel</title></head><body>
  <a href="/qisserver/rds?state=user&type=3&category=auth.logout">Abmelden</a>
  $_decoyStudienverlaufHtml
  <div id="examsReadonly:overviewAsTreeReadonly:tree:ExamOverviewForPersonTreeReadonly">
    <table class="treeTableWithIcons">
      $_headerRow
      ${_row('1', 1, 'Bachelor Angewandte Informatik')}
      ${_row('1.1', 2, 'Modul Mathematik')}
      ${_row('1.1.1', 3, 'Mathematik I', nummer: '11111', versuch: '1', bewertung: '1.7', status: 'BE', freigabedatum: '12.02.2026 10:15:00')}
      ${_row('1.1.2', 3, 'Mathematik I', nummer: '11111', versuch: '2', bewertung: '4.0', status: 'NB', vermerk: 'Nachschreiber')}
      ${_row('1.2', 2, 'Modul Programmierung')}
      ${_row('1.2.1', 3, 'Programmierung Projekt', nummer: '22222', versuch: '1', bewertung: '', bonus: '5', status: 'BE')}
      ${_row('1.3', 2, 'C-Sammelkonto', bewertung: '2.1', status: 'BE')}
      ${_row('1.3.1', 3, 'Prüfungsleistungen gesamt', nummer: '99999', bewertung: '', status: 'BE')}
      ${_row('2', 1, 'Zertifikat Zusatzqualifikation', nummer: '33333', bewertung: '', status: 'XX')}
    </table>
  </div>
</body></html>''';

/// The exam overview as the build currently deployed at Hochschule Anhalt
/// renders it for an account WITHOUT results: the `examsReadonly` form and the
/// "Leistungsdaten" section are there, but the section holds the portal's
/// "no records" info box instead of a tree — and there is no expand-all button
/// anywhere on the page.
///
/// The Studienverlauf section BELOW it does carry a `treeTableWithIcons`.
/// That is the trap this fixture pins: matching any tree table on the page
/// would read the study plan as if it were a Notenspiegel.
///
/// Anonymised replica of the live structure (ids and classes as observed on
/// 2026-08-24); no real names, numbers, modules or grades.
const String hisInOneEmptyOverviewHtml = '''
<html><head><title>Leistungen</title></head><body>
  <a href="/qisserver/rds?state=user&type=3&category=auth.logout">Abmelden</a>
  <form id="examsReadonly" name="examsReadonly" method="post"
        action="/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml?_flowId=examsOverviewForPerson-flow&_flowExecutionKey=e1s1">
    <input type="hidden" name="authenticity_token" value="TOKEN-XYZ" />
    <div id="examsReadonly:overviewAsTreeReadonly">
      <div id="examsReadonly:overviewAsTreeReadonly:fieldset" class="boxStandard">
        <h2>Leistungsdaten</h2>
        <button id="examsReadonly:overviewAsTreeReadonly:minmax" type="button">-</button>
        <fieldset id="examsReadonly:overviewAsTreeReadonly:overviewAsTreeReadonly_innerFieldset">
          <div class="helptext">
            <div class="fieldsetMessageText infoBox">Es wurden keine Datensätze gefunden.</div>
          </div>
        </fieldset>
      </div>
    </div>
    <div id="examsReadonly:degreeProgramProgressForReportAsTree">
      <h2>Studienverlauf</h2>
      <div id="examsReadonly:degreeProgramProgressForReportAsTree:studyHistoryTree">
        <table class="treeTableWithIcons">
          <tr><th class="invisible">Ebene</th><th colspan="5">Abschluss/Fächer</th></tr>
          <tr><td class="invisible">1.1</td><td colspan="5">Bachelor</td></tr>
          <tr><td class="invisible">1.1.1</td><td colspan="5">Winter 2026/27</td></tr>
        </table>
      </div>
    </div>
    <input type="hidden" name="examsReadonly_SUBMIT" value="1" />
    <input type="hidden" name="javax.faces.ViewState" value="e1s1" />
  </form>
</body></html>''';

/// The same portal build WITH results: an exam tree nested under the
/// "Leistungsdaten" section — but, like the live page, without any expand-all
/// control (nodes are toggled one by one) and without the older
/// `:tree:ExamOverviewForPersonTreeReadonly` inner id. Must be parsed as
/// rendered instead of reported as a structure change.
final String hisInOneRenderedTreeNoExpandAllHtml =
    '''
<html><head><title>Leistungen</title></head><body>
  <a href="/qisserver/rds?state=user&type=3&category=auth.logout">Abmelden</a>
  <form id="examsReadonly" method="post" action="/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml">
    <input type="hidden" name="authenticity_token" value="TOKEN-XYZ" />
    $_decoyStudienverlaufHtml
    <div id="examsReadonly:overviewAsTreeReadonly">
      <div id="examsReadonly:overviewAsTreeReadonly:examTree">
        <table class="treeTableWithIcons">
          $_headerRow
          ${_row('1', 1, 'Bachelor Angewandte Informatik')}
          ${_row('1.1', 2, 'Modul Mathematik')}
          ${_row('1.1.1', 3, 'Mathematik I', nummer: '11111', versuch: '1', bewertung: '1.7', status: 'BE')}
        </table>
      </div>
    </div>
    <input type="hidden" name="examsReadonly_SUBMIT" value="1" />
    <input type="hidden" name="javax.faces.ViewState" value="e1s1" />
  </form>
</body></html>''';

/// [hisInOneRenderedTreeNoExpandAllHtml] plus the real "Bescheinigungen"
/// print buttons, for gateway tests exercising both the grade tree and the
/// exam-report offers from one fetch.
final String hisInOneRenderedTreeWithExamReportsHtml =
    '''
<html><head><title>Leistungen</title></head><body>
  <a href="/qisserver/rds?state=user&type=3&category=auth.logout">Abmelden</a>
  <form id="examsReadonly" method="post" action="/qisserver/pages/sul/examAssessment/personExamsReadonly.xhtml">
    <input type="hidden" name="authenticity_token" value="TOKEN-XYZ" />
    $_decoyStudienverlaufHtml
    <div id="examsReadonly:overviewAsTreeReadonly">
      <div id="examsReadonly:overviewAsTreeReadonly:examTree">
        <table class="treeTableWithIcons">
          $_headerRow
          ${_row('1', 1, 'Bachelor Angewandte Informatik')}
          ${_row('1.1', 2, 'Modul Mathematik')}
          ${_row('1.1.1', 3, 'Mathematik I', nummer: '11111', versuch: '1', bewertung: '1.7', status: 'BE')}
        </table>
      </div>
    </div>
    <div id="examsReadonly:exaReports:fieldset_exaReports">
      <h2>Bescheinigungen</h2>
      <ul class="buttons_vertical">
        <li><button id="examsReadonly:exaReports:fieldset_exaReports:printReport_0"
                    name="examsReadonly:exaReports:fieldset_exaReports:printReport_0"
                    type="submit"
                    value="Leistungsübersicht (bestandene Leistungen) / List of passed exam (german) [PDF]"
                    class="submit_print_pdf immediate">
          <span>Leistungsübersicht (bestandene Leistungen) / List of passed exam (german) [PDF]</span>
        </button></li>
      </ul>
    </div>
    <input type="hidden" name="examsReadonly_SUBMIT" value="1" />
    <input type="hidden" name="javax.faces.ViewState" value="e1s1" />
  </form>
</body></html>''';

/// An expanded tree whose header is missing the required `Status` column.
final String hisInOneStructureChangedHtml =
    '''
<html><head><title>Notenspiegel</title></head><body>
  <div id="examsReadonly:overviewAsTreeReadonly:tree:ExamOverviewForPersonTreeReadonly">
    <table class="treeTableWithIcons">
      <tr><th class="invisible">Ebene</th><th colspan="9">Titel</th><th>Nummer</th><th>Bewertung</th></tr>
      ${_row('1', 1, 'Ohne Status')}
    </table>
  </div>
</body></html>''';
