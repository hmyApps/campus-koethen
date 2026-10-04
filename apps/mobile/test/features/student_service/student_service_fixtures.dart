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

/// A JSF partial-response for the `<p:poll>` widget's own component, with no
/// download link yet — the job is still running. The real widget carries no
/// discoverable "poll marker": its render target and the fixed `:poll`
/// source it polls with are both read directly off the gateway's own
/// `_pollComponentId` constant (confirmed 2026-10-04 from a real poll
/// request), not scraped from this response.
String partialResponseStarted({String viewState = 'view-state-token-5'}) =>
    '''
<?xml version='1.0' encoding='UTF-8'?>
<partial-response><changes>
<update id="studyserviceForm:report:reports:reportButtons:jobDownloadPoll"><![CDATA[
<span id="studyserviceForm:report:reports:reportButtons:jobDownloadPoll"></span>
]]></update>
<update id="j_id__v_7:javax.faces.ViewState:1"><![CDATA[$viewState]]></update>
</changes></partial-response>
''';

/// A JSF partial-response whose job has already finished — confirmed
/// 2026-10-04 from a real job-start response: the download link is already
/// present the moment the job completes, as a plain hidden `<a>`, not an
/// `<eval>` block. Its `href` is site-relative and HTML-escaped
/// (`&amp;`, since it is an attribute value inside CDATA) — the gateway
/// resolves and unescapes it, never assumes it is already absolute.
///
/// An earlier analysis had wrongly claimed a separate "untrust-" subdomain
/// for this link; a follow-up manual request to that subdomain (missing the
/// one-time, per-job `accountId`/`hash`/`timestamp`) failed and was wrongly
/// read as proof the subdomain did not exist. A REAL captured download from
/// an actual completed job (2026-10-04) settles it: the entry link stays on
/// the portal host with only `docId`, exactly as rendered below; its `307`
/// then redirects to the separate `untrust-` host with the richer parameter
/// set — see [docDownloadRedirectTarget].
String partialResponseFinished({String docId = 'abc-123'}) =>
    '''
<?xml version='1.0' encoding='UTF-8'?>
<partial-response><changes>
<update id="studyserviceForm:report:reports:reportButtons:jobDownload"><![CDATA[
<div id="studyserviceForm:report:reports:reportButtons:jobDownload">
<div id="studyserviceForm:report:reports:reportButtons:jobDownloadPoll">
<span class="polling-data-holder" style="display:none;" data-poll-button-client-id="studyserviceForm:report:reports:reportButtons:jobDownloadPoll:poll" data-timeout="3000" data-stop="false" data-is-ajax="true"></span>
<a class="downloadFile noDisplay" href="/qisserver/rds?state=docdownload&amp;docId=$docId" target="_blank">cs.sys.job.downloadManual</a>
</div></div>
]]></update>
</changes></partial-response>
''';

/// The SEPARATE-host redirect target the entry link above actually resolves
/// to once followed — confirmed 2026-10-04 from a real completed download's
/// `Location` header, independently corroborated by the portal's own
/// `Content-Security-Policy` response header listing this exact host under
/// `child-src`.
String docDownloadRedirectTarget({String docId = 'abc-123'}) =>
    'https://untrust-sscportal.ssc.hs-anhalt.de/qisserver/rds?state=docdownload'
    '&accountId=52153&hash=e09abb51206c61a0f776a5edc7848fb3'
    '&timestamp=20261004002735&docId=$docId&docName=Gebuehrenbescheinigung.pdf';
