class NetworkProfile {
  const NetworkProfile({
    this.obsHost = '192.168.1.151',
    this.horizontalPort = 9000,
    this.verticalPort = 9001,
    this.srtLatencyMs = 120,
    this.tsbpd = true,
    this.tlpktdrop = true,
    this.rtmpFallbackUrl,
  });

  final String obsHost;
  final int horizontalPort;
  final int verticalPort;
  final int srtLatencyMs;
  final bool tsbpd;
  final bool tlpktdrop;
  final String? rtmpFallbackUrl;

  static const defaults = NetworkProfile();

  NetworkProfile copyWith({
    String? obsHost,
    int? horizontalPort,
    int? verticalPort,
    int? srtLatencyMs,
    bool? tsbpd,
    bool? tlpktdrop,
    String? rtmpFallbackUrl,
  }) => NetworkProfile(
    obsHost: obsHost ?? this.obsHost,
    horizontalPort: horizontalPort ?? this.horizontalPort,
    verticalPort: verticalPort ?? this.verticalPort,
    srtLatencyMs: srtLatencyMs ?? this.srtLatencyMs,
    tsbpd: tsbpd ?? this.tsbpd,
    tlpktdrop: tlpktdrop ?? this.tlpktdrop,
    rtmpFallbackUrl: rtmpFallbackUrl ?? this.rtmpFallbackUrl,
  );

  Map<String, Object?> toMap() => {
    'obsHost': obsHost,
    'horizontalPort': horizontalPort,
    'verticalPort': verticalPort,
    'srtLatencyMs': srtLatencyMs,
    'tsbpd': tsbpd,
    'tlpktdrop': tlpktdrop,
    'rtmpFallbackUrl': rtmpFallbackUrl,
  };
}

enum WifiBand { unknown, band24GHz, band5GHz }
