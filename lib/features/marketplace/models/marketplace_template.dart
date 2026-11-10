import 'package:flutter/material.dart';
import '../../wizard/models/project_config.dart';

class TemplateManifestContext {
  final String designSystem;
  final String stateManagement;
  final String routingPattern;
  final List<String> screenNames;
  final String aiPromptRules;

  const TemplateManifestContext({
    required this.designSystem,
    required this.stateManagement,
    required this.routingPattern,
    required this.screenNames,
    required this.aiPromptRules,
  });
}

class MarketplaceTemplate {
  final String id;
  final String title;
  final String author;
  final String category;
  final String description;
  final double priceUsd;
  final double rating;
  final int reviewsCount;
  final int downloadsCount;
  final int screensCount;
  final PresetType preset;
  final NavigationStyle navigationStyle;
  final List<String> tags;
  final List<String> features;
  final Color accentColor;
  final IconData icon;
  final TemplateManifestContext manifest;

  const MarketplaceTemplate({
    required this.id,
    required this.title,
    required this.author,
    required this.category,
    required this.description,
    required this.priceUsd,
    required this.rating,
    required this.reviewsCount,
    required this.downloadsCount,
    required this.screensCount,
    required this.preset,
    required this.navigationStyle,
    required this.tags,
    required this.features,
    required this.accentColor,
    required this.icon,
    required this.manifest,
  });

  bool get isFree => priceUsd == 0.0;
  String get formattedPrice => isFree ? 'GRÁTIS' : '\$${priceUsd.toStringAsFixed(0)} USD';
}
