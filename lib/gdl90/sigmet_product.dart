import 'package:avaremp/gdl90/product.dart';

class SigmetProduct extends Product {
  SigmetProduct(super.time, super.line, super.coordinate, super.productFileId, super.productFileLength, super.apduNumber, super.segFlag);

  @override
  String decode() => graphicsSummary("SIGMET");

  @override
  String shortName() => "SIGMET";
}