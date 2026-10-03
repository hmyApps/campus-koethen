// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

/// Anonymised replica of the live "Studienservice" structure, confirmed
/// against the real portal on 2026-10-03. Ids, classes, header texts and
/// the tab buttons' real `name` attributes (JSF's own `content.N`, distinct
/// from the button's `id` and carrying no `value` attribute at all) are
/// real; every personal value (name, Matrikelnummer, address, …) is a
/// placeholder.
library;

/// The default-tab ("Meine Studiengänge") render, including the always-present
/// collapsed Personendaten block.
String studyServiceStgStudentHtml({String flowExecutionKey = 'e1s1'}) =>
    '''
<html><body>
<form id="studyserviceForm" method="post"
      action="/qisserver/pages/cm/stu/studyService/start.xhtml?_flowId=studyservice-flow&_flowExecutionKey=$flowExecutionKey">
  <input type="hidden" name="activePageElementId" value="" />
  <input type="hidden" name="javax.faces.ViewState" value="view-state-token" />
  <input type="hidden" name="authenticity_token" value="auth-token" />
  <input type="hidden" name="studyserviceForm_SUBMIT" value="1" />
  <button type="submit" id="studyserviceForm:newContactData_TabBtn"
          name="studyserviceForm:content.5" role="tab">Kontaktdaten</button>
  <button type="submit" id="studyserviceForm:billsAndPayment_TabBtn"
          name="studyserviceForm:content.8" role="tab">Zahlungen</button>
  <button type="submit" id="studyserviceForm:report_TabBtn"
          name="studyserviceForm:content.10" role="tab">Bescheide / Bescheinigungen</button>

  <div id="studyserviceForm:fieldsetPersoenlicheData">
    <div class="oneLine"><div class="labelWithBG">Matrikelnummer</div><div class="answer">000000</div></div>
    <div class="oneLine"><div class="labelWithBG">Hörerstatus</div><div class="answer">Student</div></div>
    <div class="oneLine"><div class="labelWithBG">Geburtsdatum</div><div class="answer">01.01.2000</div></div>
  </div>

  <h2>Meine Studiengänge</h2>
  <table id="studyserviceForm:stgStudent:collapsibleFieldsetCourseOfStudies:fieldsetDegreeProgram_1:degreeProgramProgresTable:degreeProgramProgresTableTable"
         class="tableWithSelect table">
    <thead><tr>
      <th class="tableHeader column0"><span>Fach</span></th>
      <th class="tableHeader column1"><span>Fachsemester</span></th>
      <th class="tableHeader column2"><span>Fachkennzeichen</span></th>
      <th class="tableHeader column3"><span>Prüfungsordnungsversion</span></th>
    </tr></thead>
    <tbody id="…Table:tbody_element">
      <tr class="listRowOdd">
        <td class="column0"><span>Informatik</span></td>
        <td class="column1"><span>3</span></td>
        <td class="column2"><span>H</span></td>
        <td class="column3"><span>2023</span></td>
      </tr>
    </tbody>
  </table>
</form>
</body></html>
''';

String studyServiceContactDataHtml({String flowExecutionKey = 'e1s2'}) =>
    '''
<html><body>
<form id="studyserviceForm" method="post"
      action="/qisserver/pages/cm/stu/studyService/start.xhtml?_flowId=studyservice-flow&_flowExecutionKey=$flowExecutionKey">
  <input type="hidden" name="javax.faces.ViewState" value="view-state-token-2" />
  <button type="submit" id="studyserviceForm:report_TabBtn"
          name="studyserviceForm:content.10" role="tab">Bescheide / Bescheinigungen</button>
  <button type="submit" id="studyserviceForm:billsAndPayment_TabBtn"
          name="studyserviceForm:content.8" role="tab">Zahlungen</button>

  <div id="studyserviceForm:fieldsetPersoenlicheData">
    <div class="oneLine"><div class="labelWithBG">Matrikelnummer</div><div class="answer">000000</div></div>
    <div class="oneLine"><div class="labelWithBG">Hörerstatus</div><div class="answer">Student</div></div>
  </div>

  <div class="tile_fieldset">
    <h2>Semesteranschrift</h2>
    <div class="postaddressDataContainer tileDataContainer">Musterstraße 1, 06366 Köthen</div>
  </div>
  <div class="tile_fieldset">
    <h2>Rechenzentrum</h2>
    <div class="emailDataContainer tileDataContainer">student@hs-anhalt.de</div>
  </div>
  <div class="tile_fieldset">
    <h2>Companyaddress for paying study-fees</h2>
    <div class="postaddressDataContainer tileDataContainer"></div>
  </div>
</form>
</body></html>
''';

String studyServiceBillsAndPaymentHtml({
  String flowExecutionKey = 'e1s3',
  bool hasOpenItems = false,
}) {
  final String body = hasOpenItems
      ? '''
  <table id="studyserviceForm:billsAndPayment:fieldSetInvoicePaid:dataTableSalesInvoicesOffenTable">
    <thead><tr><th>Zeitraum</th><th>Verwendungszweck</th><th>Soll</th><th>Ist</th></tr></thead>
    <tbody>
      <tr class="listRowOdd"><td>WS 2026/27</td><td>Semesterbeitrag</td><td>120,00</td><td>0,00</td></tr>
    </tbody>
  </table>
'''
      : '<p>Sie haben keine offenen Zahlungen!</p>';
  return '''
<html><body>
<form id="studyserviceForm" method="post"
      action="/qisserver/pages/cm/stu/studyService/start.xhtml?_flowId=studyservice-flow&_flowExecutionKey=$flowExecutionKey">
  <input type="hidden" name="javax.faces.ViewState" value="view-state-token-3" />
  <button type="submit" id="studyserviceForm:report_TabBtn"
          name="studyserviceForm:content.10" role="tab">Bescheide / Bescheinigungen</button>
  <div id="studyserviceForm:fieldsetPersoenlicheData">
    <div class="oneLine"><div class="labelWithBG">Hörerstatus</div><div class="answer">Student</div></div>
  </div>
  $body
</form>
</body></html>
''';
}

String studyServiceReportHtml({String flowExecutionKey = 'e1s4'}) =>
    '''
<html><body>
<form id="studyserviceForm" method="post"
      action="/qisserver/pages/cm/stu/studyService/start.xhtml?_flowId=studyservice-flow&_flowExecutionKey=$flowExecutionKey">
  <input type="hidden" name="javax.faces.ViewState" value="view-state-token-4" />
  <div id="studyserviceForm:fieldsetPersoenlicheData">
    <div class="oneLine"><div class="labelWithBG">Hörerstatus</div><div class="answer">Student</div></div>
  </div>
  <li class="job-configuration-buttons-item group">
    <h3 class="groupname">Bescheinigungen:</h3>
    <ul class="job-configuration-buttons vertical">
      <li class="job-configuration-buttons-item job">
        <button id="studyserviceForm:report:reports:reportButtons:jobConfigurationButtons:0:jobConfigurationButtons:0:job2"
                type="submit" class="submit_linkLook job-configuration-buttons-button short-waiting-behavior">
          <span class="jobname">Gebührenbescheinigung</span>
        </button>
      </li>
      <li class="job-configuration-buttons-item job">
        <button id="studyserviceForm:report:reports:reportButtons:jobConfigurationButtons:0:jobConfigurationButtons:1:job2"
                type="submit" class="submit_linkLook job-configuration-buttons-button short-waiting-behavior">
          <span class="jobname">Studienverlaufsbescheinigung</span>
        </button>
      </li>
    </ul>
  </li>
</form>
</body></html>
''';

/// A JSF partial-response that renders a "poll" marker but no download link
/// yet — the job just started.
String partialResponseStarted({
  String pollButtonId =
      'studyserviceForm:report:reports:reportButtons:jobDownloadPoll',
  String viewState = 'view-state-token-5',
}) =>
    '''
<?xml version='1.0' encoding='UTF-8'?>
<partial-response><changes>
<update id="studyserviceForm:report:reports:reportButtons:jobDownload"><![CDATA[
<div id="studyserviceForm:report:reports:reportButtons:jobDownload">
  <span class="polling-data-holder" data-poll-button-client-id="$pollButtonId"
        data-timeout="60000" data-stop="false" data-is-ajax="true"></span>
</div>
]]></update>
<update id="javax.faces.ViewState"><![CDATA[$viewState]]></update>
</changes></partial-response>
''';

/// A JSF partial-response whose job has finished: the eval block navigates to
/// the one-time download link.
String partialResponseFinished({
  String docId = 'abc-123',
  String hash = 'deadbeef',
}) =>
    '''
<?xml version='1.0' encoding='UTF-8'?>
<partial-response><changes>
<update id="studyserviceForm:report:reports:reportButtons:jobDownload"><![CDATA[
<div id="studyserviceForm:report:reports:reportButtons:jobDownload">done</div>
]]></update>
<eval><![CDATA[
window.location = 'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds?state=docdownload&accountId=1&hash=$hash&timestamp=20261001120000&docId=$docId&docName=Gebuehrenbescheinigung.pdf';
]]></eval>
</changes></partial-response>
''';
