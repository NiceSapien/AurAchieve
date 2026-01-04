import 'package:flutter_quill/quill_delta.dart';

String deltaToMarkdown(Delta delta) {
  final buffer = StringBuffer();
  final lines = <String>[];
  
  
  
  
  
  String currentLine = '';
  Map<String, dynamic>? currentLineAttrs;
  
  for (final op in delta.toList()) {
    if (op.data is! String) continue; 
    
    String text = op.data as String;
    final attrs = op.attributes;
    
    
    if (text.contains('\n')) {
      final parts = text.split('\n');
      for (int i = 0; i < parts.length; i++) {
        final part = parts[i];
        
        if (part.isNotEmpty) {
          currentLine += _applyInlineStyles(part, attrs);
        }
        
        if (i < parts.length - 1) {
          
          
          
          
          
          
          
          
          
          
          String linePrefix = '';
          if (attrs != null) {
            if (attrs.containsKey('header')) {
              final level = attrs['header'];
              linePrefix = '${'#' * level} ';
            }
            if (attrs.containsKey('list')) {
              if (attrs['list'] == 'ordered') {
                linePrefix = '1. ';
              } else {
                linePrefix = '- ';
              }
            }
            if (attrs.containsKey('code-block')) {
               
               
            }
            if (attrs.containsKey('blockquote')) {
              linePrefix = '> ';
            }
          }
          
          lines.add('$linePrefix$currentLine');
          currentLine = '';
        }
      }
    } else {
      currentLine += _applyInlineStyles(text, attrs);
    }
  }
  
  if (currentLine.isNotEmpty) {
    lines.add(currentLine);
  }
  
  return lines.join('\n');
}

String _applyInlineStyles(String text, Map<String, dynamic>? attrs) {
  if (attrs == null) return text;
  
  String result = text;
  
  if (attrs.containsKey('bold') && attrs['bold'] == true) {
    result = '**$result**';
  }
  
  if (attrs.containsKey('italic') && attrs['italic'] == true) {
    result = '*$result*';
  }
  
  if (attrs.containsKey('underline') && attrs['underline'] == true) {
    
    result = '<ins>$result</ins>';
  }
  
  if (attrs.containsKey('strike') && attrs['strike'] == true) {
    result = '~~$result~~';
  }
  
  if (attrs.containsKey('code') && attrs['code'] == true) {
    result = '`$result`';
  }
  
  if (attrs.containsKey('link')) {
    result = '[$result](${attrs['link']})';
  }
  
  return result;
}
