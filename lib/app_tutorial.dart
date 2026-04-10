import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

TargetFocus tutorialTarget({
  required GlobalKey key,
  required String id,
  required String title,
  required String body,
  ContentAlign align = ContentAlign.bottom,
  double yOffset = 0,
}) {
  return TargetFocus(
    identify: id,
    keyTarget: key,
    alignSkip: Alignment.topRight,
    contents: [
      TargetContent(
        align: align,
        customPosition: yOffset == 0
            ? null
            : CustomTargetContentPosition(top: yOffset),
        builder: (context, controller) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: controller.skip,
                        child: const Text('Skip'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: controller.next,
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );
}
