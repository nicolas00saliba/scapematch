import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';

/// Reminds the reader that every venue, room, and group is invented.
class ExampleDataBanner extends StatelessWidget {
  const ExampleDataBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Aviso: os dados desta versão são fictícios e servem só como exemplo.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.copperSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: AppColors.copper, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Dados de exemplo. Casas, salas, horários, grupos e notícias são fictícios.',
                style: TextStyle(
                  color: AppColors.copperInk,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
