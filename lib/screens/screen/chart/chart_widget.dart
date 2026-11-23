import 'package:streambeats/src/rust/api/plugin/models.dart';
import 'package:flutter/material.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:streambeats/utils/load_image.dart';
import 'package:responsive_framework/responsive_framework.dart';

class ChartWidget extends StatelessWidget {
  final ChartSummary chart;
  final String pluginId;

  const ChartWidget({
    super.key,
    required this.chart,
    required this.pluginId,
  });

  @override
  Widget build(BuildContext context) {
    final artwork = chart.thumbnail;
    final thumbnailUrl = artwork?.urlHigh ?? artwork?.url ?? artwork?.urlLow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Teks editorial di atas kartu
        Text(
          'DENGARKAN SEKARANG',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          chart.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                  LoadImageCached(
                    imageUrl: thumbnailUrl,
                    fallbackUrl: artwork?.url ?? thumbnailUrl,
                    fit: BoxFit.cover,
                  )
                else
                  const _ChartPlaceholder(),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.78),
                        ],
                        stops: const [0.45, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 74,
                  bottom: 16,
                  child: Text(
                    (chart.description != null && chart.description!.isNotEmpty)
                        ? chart.description!
                        : chart.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFCFBCFF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(MingCute.play_fill,
                        size: 22, color: Color(0xFF2E1A66)),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ],
    );
  }
}

class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Center(
        child: Icon(
          MingCute.music_2_fill,
          size: 56,
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}