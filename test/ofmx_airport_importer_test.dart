import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofmx_importer.dart';

void main() {
  test('parses airport, communication, runway, and runway end', () {
    final result = OfmxImporter.parse(
      _airportFixture,
      region: 'EB',
      cycle: '2601',
    );

    expect(result.airports, hasLength(1));
    final airport = result.airports.single;
    expect(airport['id'], 'EB:2601:airport-1');
    expect(airport['code_id'], 'EBAW');
    expect(airport['name'], 'ANTWERPEN/DEURNE');
    expect(airport['lat'], closeTo(51.18945833, 0.000000001));
    expect(airport['lon'], closeTo(4.46039722, 0.000000001));
    expect(airport['elevation_ft'], 39);

    expect(result.airportComms, hasLength(2));
    final radio = result.airportComms.singleWhere((row) => row['code_type'] == 'TWR');
    expect(radio['airport_id'], 'EB:2601:airport-1');
    expect(radio['value'], '120.055 MHZ');
    expect(radio['remark'], 'ANTWERP TWR (EN)');
    expect(result.runways.single['designation'], '11/29');
    expect(result.runways.single['id'], 'EB:2601:runway-1');
    expect(result.runways.single['length_m'], 1510);
    expect(result.runwayEnds.single['designation'], '11');
    expect(result.runwayEnds.single['runway_id'], 'EB:2601:runway-1');
    expect(result.runwayEnds.single['mag_bearing'], 112);
  });
}

const _airportFixture = '''
<OFMX-Snapshot regions="EB">
  <Ahp><AhpUid region="EB" mid="airport-1"><codeId>EBAW</codeId></AhpUid><txtName>ANTWERPEN/DEURNE</txtName><codeIcao>EBAW</codeIcao><codeIata>ANR</codeIata><codeGps>EBDEURNE</codeGps><codeType>AH</codeType><geoLat>51.18945833N</geoLat><geoLong>004.46039722E</geoLong><valElev>39</valElev><uomDistVer>FT</uomDistVer><txtNameCitySer>ANTWERPEN</txtNameCitySer></Ahp>
  <Aha><AhaUid mid="comm-1"><AhpUid mid="airport-1"><codeId>EBAW</codeId></AhpUid><codeType>PHONE</codeType><noSeq>1</noSeq></AhaUid><txtAddress>+32 3 285 65 00</txtAddress><txtRmk>Airport office</txtRmk></Aha>
  <Uni><UniUid region="EB" mid="unit-1"><txtName>ANTWERPEN</txtName><codeType>TWR</codeType></UniUid><AhpUid region="EB" mid="airport-1"><codeId>EBAW</codeId></AhpUid></Uni>
  <Ser><SerUid mid="service-1"><UniUid region="EB" mid="unit-1"><txtName>ANTWERPEN</txtName><codeType>TWR</codeType></UniUid><codeType>TWR</codeType><noSeq>2</noSeq></SerUid></Ser>
  <Fqy><FqyUid mid="frequency-1"><SerUid mid="service-1"><UniUid region="EB" mid="unit-1"><txtName>ANTWERPEN</txtName><codeType>TWR</codeType></UniUid><codeType>TWR</codeType><noSeq>2</noSeq></SerUid><valFreqTrans>120.055</valFreqTrans></FqyUid><uomFreq>MHZ</uomFreq><codeType>STD</codeType><Cdl><txtCallSign>ANTWERP TWR (EN)</txtCallSign></Cdl></Fqy>
  <Rwy><RwyUid mid="runway-1"><AhpUid mid="airport-1"><codeId>EBAW</codeId></AhpUid><txtDesig>11/29</txtDesig></RwyUid><valLen>1510</valLen><valWid>45</valWid><uomDimRwy>M</uomDimRwy><codeComposition>ASPH</codeComposition><codeCondSfc>GOOD</codeCondSfc></Rwy>
  <Rdn><RdnUid mid="end-11"><RwyUid mid="runway-1"><AhpUid mid="airport-1"><codeId>EBAW</codeId></AhpUid><txtDesig>11/29</txtDesig></RwyUid><txtDesig>11</txtDesig></RdnUid><geoLat>51.19186111N</geoLat><geoLong>004.454775E</geoLong><valTrueBrg>109.8</valTrueBrg><valMagBrg>112</valMagBrg><valElevTdz>39</valElevTdz><uomElevTdz>FT</uomElevTdz><codeTypeVasis>PAPI</codeTypeVasis><codeVfrPattern>E</codeVfrPattern></Rdn>
</OFMX-Snapshot>
''';
