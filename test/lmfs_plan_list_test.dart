import 'package:avaremp/plan/plan_lmfs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("missing summary is an empty list", () {
    final LmfsPlanList list = LmfsPlanList("{}");
    expect(list.getPlans(), isEmpty);
    expect(list.error, isEmpty);
  });

  test("plain-text service rejection is the error", () {
    final LmfsPlanList list = LmfsPlanList(
        "Service not allowed because user or data is invalid");
    expect(list.getPlans(), isEmpty);
    expect(list.error, "Service not allowed because user or data is invalid");
  });

  test("username failure message comes from the JSON envelope", () {
    final LmfsPlanList list = LmfsPlanList(
        '{"returnStatus":false,"returnMessage":["User Name does not exist."],"returnCodedMessage":[],"flightPlanSummary":[]}');
    expect(list.getPlans(), isEmpty);
    expect(list.error, "User Name does not exist.");
  });

  test("domestic summaries use nas fields when icao fields are null", () {
    final LmfsPlanList list = LmfsPlanList('''
      {"returnStatus":true,"flightPlanSummary":[{
        "versionStamp":"20150112162243160",
        "aircraftIdentifier":"N172EF",
        "currentState":"PROPOSED",
        "flightId":"66052270_527360_258",
        "icaoSummaryFields":null,
        "nasSummaryFields":{
          "destination":{"locationIdentifier":"MIA"},
          "departure":{"locationIdentifier":"HOU"}
        }
      }]}
    ''');
    expect(list.error, isEmpty);
    expect(list.getPlans(), hasLength(1));
    expect(list.getPlans().single.departure, "HOU");
    expect(list.getPlans().single.destination, "MIA");
    expect(list.getPlans().single.aircraftId, "N172EF");
    expect(list.getPlans().single.currentState, "PROPOSED");
  });
}
