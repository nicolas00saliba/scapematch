import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';

/// Cinco estrelas, com meia estrela no 0,5 mais próximo.
class ReviewStars extends StatelessWidget {
  const ReviewStars({super.key, required this.average, this.size = 22});

  final double average;
  final double size;

  @override
  Widget build(BuildContext context) {
    final stars = starRow(average);
    final color = Theme.of(context).colorScheme.secondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final star in stars)
          Icon(
            switch (star) {
              StarFill.full => Icons.star,
              StarFill.half => Icons.star_half,
              StarFill.empty => Icons.star_border,
            },
            size: size,
            color: color,
          ),
      ],
    );
  }
}

/// Nota geral em estrelas e número, com uma casa decimal.
class ReviewOverallLine extends StatelessWidget {
  const ReviewOverallLine({
    super.key,
    required this.average,
    this.count,
    this.starKey,
  });

  final double average;
  final int? count;
  final Key? starKey;

  @override
  Widget build(BuildContext context) {
    final number = average.toStringAsFixed(1).replaceAll('.', ',');
    final suffix = count == null
        ? ''
        : ' · $count ${count == 1 ? 'avaliação' : 'avaliações'}';
    return Row(
      children: [
        ReviewStars(key: starKey, average: average),
        const SizedBox(width: 8),
        Text(
          '$number$suffix',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
