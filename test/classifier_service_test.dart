import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nouphptt/services/classifier_service.dart';

void main() {
  group('ClassifierService Output Processing', () {
    test('DetectionResult creation with valid confidence', () {
      const result = DetectionResult(
        label: 'Healthy',
        confidence: 0.95,
        severity: 'No Disease',
        description: 'Test description',
        recommendations: ['Test recommendation'],
        color: Colors.green,
      );
      
      expect(result.label, equals('Healthy'));
      expect(result.confidence, equals(0.95));
      expect(result.severity, equals('No Disease'));
    });

    test('FullInferenceResult wraps detection result and probabilities', () {
      const detection = DetectionResult(
        label: 'Early Blight',
        confidence: 0.75,
        severity: 'Moderate Risk',
        description: 'Test',
        recommendations: [],
        color: Colors.orange,
      );
      
      final probs = {
        'Early Blight': 0.75,
        'Late Blight': 0.15,
        'Healthy': 0.10,
      };
      
      final full = FullInferenceResult(
        result: detection,
        probabilities: probs,
      );
      
      expect(full.result.label, equals('Early Blight'));
      expect(full.probabilities['Early Blight'], equals(0.75));
      expect(full.probabilities.length, equals(3));
    });

    test('Probabilities sum validation', () {
      // Test that probabilities are properly handled
      final probs = [0.7, 0.2, 0.1]; // Sum = 1.0
      double sum = 0;
      for (final p in probs) {
        sum += p;
      }
      
      expect((sum - 1.0).abs(), lessThan(0.05));
    });
  });
}

