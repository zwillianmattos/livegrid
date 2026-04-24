enum ThermalStatus {
  none(0),
  light(1),
  moderate(2),
  severe(3),
  critical(4),
  emergency(5),
  shutdown(6);

  const ThermalStatus(this.code);
  final int code;

  static ThermalStatus fromCode(int? code) {
    if (code == null) return ThermalStatus.none;
    for (final s in ThermalStatus.values) {
      if (s.code == code) return s;
    }
    return ThermalStatus.none;
  }

  bool get shouldDegrade => index >= moderate.index;
  bool get shouldStop => index >= emergency.index;
}
