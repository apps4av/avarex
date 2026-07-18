import 'package:flutter/material.dart';

/// Read-only row of stars for an average/whole rating.
class StarRating extends StatelessWidget {
  final double rating; // 0..5
  final double size;

  const StarRating({super.key, required this.rating, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final color = Colors.amber.shade700;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating - i;
        IconData icon;
        if (filled >= 0.75) {
          icon = Icons.star;
        } else if (filled >= 0.25) {
          icon = Icons.star_half;
        } else {
          icon = Icons.star_border;
        }
        return Icon(icon, size: size, color: color);
      }),
    );
  }
}

/// Interactive 1..5 star selector used when composing a review.
class StarRatingInput extends StatelessWidget {
  final int value; // 1..5, 0 = none
  final ValueChanged<int> onChanged;
  final double size;

  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final color = Colors.amber.shade700;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final index = i + 1;
        return IconButton(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          constraints: const BoxConstraints(),
          icon: Icon(
            index <= value ? Icons.star : Icons.star_border,
            size: size,
            color: color,
          ),
          onPressed: () => onChanged(index),
        );
      }),
    );
  }
}
