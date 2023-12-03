import 'package:avaremp/constants.dart';

class Pan
{
  double _moveX;
  double _moveY;
  int _moveXTile;
  int _moveYTile;
  int _moveXTileOld;
  int _moveYTileOld;

  Pan(this._moveX, this._moveY, this._moveXTile, this._moveYTile, this._moveXTileOld, this._moveYTileOld);

  static Pan init() {
    return Pan(0, 0, 0, 0, 0, 0);
  }

  static Pan initFromPan(Pan p)
  {
    return Pan(p._moveX, p._moveY, p._moveXTile, p._moveYTile, p._moveXTileOld, p._moveYTileOld);
  }

  bool setMove(double x, double y)
  {
    _moveX = x;
    _moveY = y;
    bool update = false;
    int xOld = (-(_moveX ~/ Constants.tileWidth)).round();
    if (xOld != _moveXTileOld) {
      _moveXTileOld = xOld;
      update = true;
    }
    int yOld = (-(_moveY ~/ Constants.tileHeight)).round();
    if (yOld != _moveYTileOld) {
      _moveYTileOld = yOld;
      update = true;
    }
    return update;
  }

  void setTileMove(int x, int y)
  {
    _moveXTile = x;
    _moveYTile = y;
  }

  double getMoveX()
  {
    return _moveX;
  }

  double getMoveY()
  {
    return _moveY;
  }

  int getTileMoveX()
  {
    return _moveXTile;
  }

  int getTileMoveY()
  {
    return _moveYTile;
  }

  int getTileMoveXWithoutTear()
  {
    return _moveXTileOld;
  }

  int getTileMoveYWithoutTear()
  {
    return _moveYTileOld;
  }
}