class Scale
{
  double _scaleFactor;
  int _macro;
  final double _maxScale;

  double get maxScale => _maxScale;
  final double _minScale;

  Scale(this._maxScale, this._minScale, this._macro, this._scaleFactor);

  static Scale m(double max)
  {
    return Scale(max, 0.03125, 1, 1);
  }

  static Scale mm(double max, double min)
  {
    return Scale(max, min, 1, 1);
  }

  static Scale n() {
    return Scale(4, 0.03125, 1, 1);
  }

  double getStep()
  {
    double step;
    int macro = getMacroFactor();
    double scaleRaw = getScaleFactor();
    if ((macro <= 1) && (scaleRaw > 1)) {
      step = 2.5;
    } else {
      if ((macro <= 1) && (scaleRaw <= 1)) {
        step = 5;
      } else {
        if (macro <= 2) {
          step = 10;
        } else {
          if (macro <= 4) {
            step = 20;
          } else {
            if (macro <= 8) {
              step = 40;
            } else {
              step = 80;
            }
          }
        }
      }
    }
    return step;
  }

  void setScaleFactor(double factor)
  {
    _scaleFactor = factor;
  }

  double getScaleFactor()
  {
    double s;
    if (_scaleFactor > _maxScale) {
      s = _maxScale;
    } else {
      if (_scaleFactor < _minScale) {
        s = _minScale;
      } else {
        s = _scaleFactor;
      }
    }
    return s;
  }

  int getMacroFactor()
  {
    return _macro;
  }

  void setMacroFactor()
  {
    if (_scaleFactor >= 0.5) {
      _macro = 1;
    } else {
      if (_scaleFactor >= 0.25) {
        _macro = 2;
      } else {
        if (_scaleFactor >= 0.125) {
          _macro = 4;
        } else {
          if (_scaleFactor >= 0.0625) {
            _macro = 8;
          } else {
            _macro = 16;
          }
        }
      }
    }
  }

  int getNewMacroFactor()
  {
    if (_scaleFactor >= 0.5) {
      return 1;
    } else {
      if (_scaleFactor >= 0.25) {
        return 2;
      } else {
        if (_scaleFactor >= 0.125) {
          return 4;
        } else {
          if (_scaleFactor >= 0.0625) {
            return 8;
          }
        }
      }
    }
    return 16;
  }

  int downSample()
  {
    if (_scaleFactor >= 0.5) {
      return 0;
    } else {
      if (_scaleFactor >= 0.25) {
        return 1;
      } else {
        if (_scaleFactor >= 0.125) {
          return 2;
        } else {
          if (_scaleFactor >= 0.0625) {
            return 3;
          }
        }
      }
    }
    return 4;
  }

  void zoomOut()
  {
    _scaleFactor = _minScale;
  }

  double get minScale => _minScale;
}