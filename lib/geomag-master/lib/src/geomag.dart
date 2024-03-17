import 'dart:math';

import 'wmm_cof.dart';
import 'wmm_cof_data.dart';

typedef _CalcFunction = GeoMagResult Function(double glat, double glon,
    [double hFeet, DateTime? date]);

/// Translate GPS location data to geo-magnetic data such as magnetic declination.
///
/// [GeoMag] takes data from the World Magnetic Model Coefficients, [WmmCof],
/// to initialize. You can provide your own or use the bundled data from 2020.
/// Use [calculate()] to process GPS coordinates into a
/// [GeoMagResult].
///
/// See http://www.ngdc.noaa.gov/geomag/WMM/DoDWMM.shtml and
/// https://www.ngdc.noaa.gov/geomag/WMM/wmm_rdownload.shtml.
///
/// This is a port of the geomagJS package,
/// https://github.com/cmweiss/geomagJS.
///
/// > Adapted from the geomagc software and World Magnetic Model of the NOAA
/// > Satellite and Information Service, National Geophysical Data Center.
class GeoMag {
  static GeoMag? _bundledInstance;
  factory GeoMag() =>
      _bundledInstance ??= GeoMag.fromWmmCof(WmmCof.fromString(wmmCofData));
  GeoMag.fromWmmCof(WmmCof wmmCof) : _calcFunction = _geoMagFactory(wmmCof);
  final _CalcFunction _calcFunction;

  /// Calculate various geomagnetic values based on your latitude, longitude.
  GeoMagResult calculate(double lat, double lng,
      [double heightFeet = 0, DateTime? date]) {
    return _calcFunction(lat, lng, heightFeet, date);
  }

  static _CalcFunction _geoMagFactory(WmmCof wmm) {
    double rad2deg(rad) {
      return rad * (180 / pi);
    }

    double deg2rad(deg) {
      return deg * (pi / 180);
    }

    var epoch = wmm.epoch,
        z = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        maxord = 12,
        tc = [
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1)
        ],
        sp = z.sublist(1),
        cp = z.sublist(1),
        pp = z.sublist(1),
        p = [
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1)
        ],
        dp = [
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1)
        ],
        a = 6378.137,
        b = 6356.7523142,
        re = 6371.2,
        a2 = a * a,
        b2 = b * b,
        c2 = a2 - b2,
        a4 = a2 * a2,
        b4 = b2 * b2,
        c4 = a4 - b4,
        c = [
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1)
        ],
        cd = [
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1)
        ],
        snorm = [
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1)
        ],
        j,
        k = [
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1),
          z.sublist(1)
        ],
        flnmj,
        fn = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
        fm = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

    tc[0][0] = 0;
    sp[0] = 0.0;
    cp[0] = 1.0;
    pp[0] = 1.0;
    p[0][0] = 1;

    for (var i in wmm.wmm) {
      var m = i.m - 0, n = i.n - 0;
      if (m <= n) {
        c[m][n] = i.gnm;
        cd[m][n] = i.dgnm;
        if (m != 0) {
          c[n][m - 1] = i.hnm;
          cd[n][m - 1] = i.dhnm;
        }
      }
    }
    // wmm = null;

    /* CONVERT SCHMIDT NORMALIZED GAUSS COEFFICIENTS TO UNNORMALIZED */
    snorm[0][0] = 1;

    for (var n = 1; n <= maxord; n++) {
      snorm[0][n] = snorm[0][n - 1] * (2 * n - 1) / n;
      j = 2;

      var m = 0;
      for (var D2 = (n - m + 1); D2 > 0; D2--, m++) {
        k[m][n] = (((n - 1) * (n - 1)) - (m * m)) / ((2 * n - 1) * (2 * n - 3));
        if (m > 0) {
          flnmj = ((n - m + 1) * j) / (n + m);
          snorm[m][n] = snorm[m - 1][n] * sqrt(flnmj);
          j = 1;
          c[n][m - 1] = snorm[m][n] * c[n][m - 1];
          cd[n][m - 1] = snorm[m][n] * cd[n][m - 1];
        }
        c[m][n] = snorm[m][n] * c[m][n];
        cd[m][n] = snorm[m][n] * cd[m][n];
      }
    }
    k[1][1] = 0.0;

    return (double glat, double glon, [double hFeet = 0, DateTime? date]) {
      double decimalDate(DateTime? date) {
        date ??= DateTime.now();
        var year = date.year,
            daysInYear = 365 +
                (((year % 400 == 0) || (year % 4 == 0 && (year % 100 > 0)))
                    ? 1
                    : 0),
            msInYear = daysInYear * 24 * 60 * 60 * 1000;

        return date.year +
            (date.difference(DateTime(date.year, 1, 1)).inMilliseconds /
                msInYear);
      }

      var alt = hFeet /
              3280.8399, // convert h (in feet) to kilometers or set default of 0
          time = decimalDate(date);
      double dt = time - epoch,
          rlat = deg2rad(glat),
          rlon = deg2rad(glon),
          srlon = sin(rlon),
          srlat = sin(rlat),
          crlon = cos(rlon),
          crlat = cos(rlat),
          srlat2 = srlat * srlat,
          crlat2 = crlat * crlat,
          q,
          q1,
          q2,
          ct,
          st,
          r2,
          r,
          d,
          ca,
          sa,
          aor,
          ar,
          br = 0.0,
          bt = 0.0,
          bp = 0.0,
          bpp = 0.0,
          par,
          temp1,
          temp2,
          parp,
          bx,
          by,
          bz,
          bh,
          ti,
          dec,
          dip,
          gv = 0.0;
      sp[1] = srlon;
      cp[1] = crlon;

      /* CONVERT FROM GEODETIC COORDS. TO SPHERICAL COORDS. */
      q = sqrt(a2 - c2 * srlat2);
      q1 = alt * q;
      q2 = ((q1 + a2) / (q1 + b2)) * ((q1 + a2) / (q1 + b2));
      ct = srlat / sqrt(q2 * crlat2 + srlat2);
      st = sqrt(1.0 - (ct * ct));
      r2 = (alt * alt) + 2.0 * q1 + (a4 - c4 * srlat2) / (q * q);
      r = sqrt(r2);
      d = sqrt(a2 * crlat2 + b2 * srlat2);
      ca = (alt + d) / r;
      sa = c2 * crlat * srlat / (r * d);

      for (var m = 2; m <= maxord; m++) {
        sp[m] = sp[1] * cp[m - 1] + cp[1] * sp[m - 1];
        cp[m] = cp[1] * cp[m - 1] - sp[1] * sp[m - 1];
      }

      aor = re / r;
      ar = aor * aor;

      for (var n = 1; n <= maxord; n++) {
        ar = ar * aor;
        var m = 0;
        for (var D4 = (n + m + 1); D4 > 0; D4--, m++) {
          /*
				  COMPUTE UNNORMALIZED ASSOCIATED LEGENDRE POLYNOMIALS
			  	AND DERIVATIVES VIA RECURSION RELATIONS
		      */
          if (n == m) {
            p[m][n] = st * p[m - 1][n - 1];
            dp[m][n] = st * dp[m - 1][n - 1] + ct * p[m - 1][n - 1];
          } else if (n == 1 && m == 0) {
            p[m][n] = ct * p[m][n - 1];
            dp[m][n] = ct * dp[m][n - 1] - st * p[m][n - 1];
          } else if (n > 1 && n != m) {
            if (m > n - 2) {
              p[m][n - 2] = 0;
            }
            if (m > n - 2) {
              dp[m][n - 2] = 0.0;
            }
            p[m][n] = ct * p[m][n - 1] - k[m][n] * p[m][n - 2];
            dp[m][n] =
                ct * dp[m][n - 1] - st * p[m][n - 1] - k[m][n] * dp[m][n - 2];
          }

          /*
				  TIME ADJUST THE GAUSS COEFFICIENTS
		      */

          tc[m][n] = c[m][n] + dt * cd[m][n];
          if (m != 0) {
            tc[n][m - 1] = c[n][m - 1] + dt * cd[n][m - 1];
          }

          /*
				  ACCUMULATE TERMS OF THE SPHERICAL HARMONIC EXPANSIONS
		      */
          par = ar * p[m][n];
          if (m == 0) {
            temp1 = tc[m][n] * cp[m];
            temp2 = tc[m][n] * sp[m];
          } else {
            temp1 = tc[m][n] * cp[m] + tc[n][m - 1] * sp[m];
            temp2 = tc[m][n] * sp[m] - tc[n][m - 1] * cp[m];
          }
          bt = bt - ar * temp1 * dp[m][n];
          bp += (fm[m] * temp2 * par);
          br += (fn[n] * temp1 * par);
          /*
					SPECIAL CASE:  NORTH/SOUTH GEOGRAPHIC POLES
		      */
          if (st == 0.0 && m == 1) {
            if (n == 1) {
              pp[n] = pp[n - 1];
            } else {
              pp[n] = ct * pp[n - 1] - k[m][n] * pp[n - 2];
            }
            parp = ar * pp[n];
            bpp += (fm[m] * temp2 * parp);
          }
        }
      }

      bp = (st == 0.0 ? bpp : bp / st);
      /*
			ROTATE MAGNETIC VECTOR COMPONENTS FROM SPHERICAL TO
			GEODETIC COORDINATES
		  */
      bx = -bt * ca - br * sa;
      by = bp;
      bz = bt * sa - br * ca;

      /*
			COMPUTE DECLINATION (DEC), INCLINATION (DIP) AND
			TOTAL INTENSITY (TI)
		  */
      bh = sqrt((bx * bx) + (by * by));
      ti = sqrt((bh * bh) + (bz * bz));
      dec = rad2deg(atan2(by, bx));
      dip = rad2deg(atan2(bz, bh));

      /*
			COMPUTE MAGNETIC GRID VARIATION IF THE CURRENT
			GEODETIC POSITION IS IN THE ARCTIC OR ANTARCTIC
			(I.E. GLAT > +55 DEGREES OR GLAT < -55 DEGREES)
			OTHERWISE, SET MAGNETIC GRID VARIATION TO -999.0
		  */

      if (glat.abs() >= 55.0) {
        if (glat >= 0.0 && glon >= 0.0) {
          gv = dec - glon;
        } else if (glat >= 0.0 && glon < 0.0) {
          gv = dec + glon.abs();
        } else if (glat < 0.0 && glon >= 0.0) {
          gv = dec + glon;
        } else if (glat < 0.0 && glon < 0.0) {
          gv = dec - glon.abs();
        }
        if (gv > 180.0) {
          gv -= 360.0;
        } else if (gv < -180.0) {
          gv += 360.0;
        }
      }

      return GeoMagResult._(
          dec, dip, ti, bh, bx, by, bz, glat, glon, gv, epoch);
    };
  }
}

/// The result of calculating your magnetic declination and other values.
class GeoMagResult {
  const GeoMagResult._(this.dec, this.dip, this.ti, this.bh, this.bx, this.by,
      this.bz, this.lat, this.lon, this.gv, this.time);

  /// Declination in degrees east of geographic north.
  final double dec;
  final double dip;
  final double ti;
  final double bh;
  final double bx;
  final double by;
  final double bz;

  /// Latitude
  final double lat;

  /// Longitude
  final double lon;
  final double gv;

  /// Years since the [WmmCof.epoch].
  final double time;

  @override
  String toString() =>
      '{dec: $dec, dip: $dip, ti: $ti, bh: $bh, bx: $bx, by: $by, bz: $bz, lat: $lat, lon: $lon, gv: $gv}';
}
