// server/src/modules/notification/template_parser.service.ts
// Serenut Platform — Dynamic Template Engine Service (Sprint 9)
// Parses template body expressions like {{customer}} or {{total}} with custom payload data.
// Created: 04 Jul 2026

export class TemplateParserService {
  /**
   * Resolves mustache-like variables in text with provided dictionary object.
   * If a value is missing, it is replaced with empty string.
   */
  public static parse(template: string, payload: Record<string, any>): string {
    if (!template) return '';
    
    // Regular expression matching double curly braces {{variable}}
    const regex = /\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g;

    return template.replace(regex, (match, variableName) => {
      const value = payload[variableName];
      if (value === undefined || value === null) {
        return '';
      }
      
      // Basic escaping/sanitization to prevent raw shell script injection
      return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#x27;');
    });
  }
}
