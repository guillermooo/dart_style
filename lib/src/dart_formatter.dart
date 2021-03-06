// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart_style.src.code_formatter;

import 'package:analyzer/src/string_source.dart';
import 'package:analyzer/src/generated/parser.dart';
import 'package:analyzer/src/generated/scanner.dart';
import 'package:analyzer/src/generated/source.dart';

import 'error_listener.dart';
import 'source_visitor.dart';

/// Describes a chunk of source code that is to be formatted or has been
/// formatted.
class SourceCode {
  /// The [uri] where the source code is from.
  ///
  /// Used in error messages if the code cannot be parsed.
  final String uri;

  /// The Dart source code text.
  final String text;

  /// Whether the source is a compilation unit or a bare statement.
  final bool isCompilationUnit;

  /// The offset in [text] where the selection begins, or `null` if there is
  /// no selection.
  final int selectionStart;

  /// The number of selected characters or `null` if there is no selection.
  final int selectionLength;

  SourceCode(this.text,
      {this.uri, this.isCompilationUnit: true, this.selectionStart,
      this.selectionLength}) {
    // Must either provide both selection bounds or neither.
    if ((selectionStart == null) != (selectionLength == null)) {
      throw new ArgumentError(
          "Is selectionStart is provided, selectionLength must be too.");
    }

    if (selectionStart != null) {
      if (selectionStart < 0) {
        throw new ArgumentError("selectionStart must be non-negative.");
      }

      if (selectionStart > text.length) {
        throw new ArgumentError("selectionStart must be within text.");
      }
    }

    if (selectionLength != null) {
      if (selectionLength < 0) {
        throw new ArgumentError("selectionLength must be non-negative.");
      }

      if (selectionStart + selectionLength > text.length) {
        throw new ArgumentError("selectionLength must end within text.");
      }
    }
  }
}

/// Dart source code formatter.
class DartFormatter {
  /// The string that newlines should use.
  ///
  /// If not explicitly provided, this is inferred from the source text. If the
  /// first newline is `\r\n` (Windows), it will use that. Otherwise, it uses
  /// Unix-style line endings (`\n`).
  String lineEnding;

  /// The number of characters allowed in a single line.
  final int pageWidth;

  /// The number of levels of indentation to prefix the output lines with.
  final int indent;

  /// Creates a new formatter for Dart code.
  ///
  /// If [lineEnding] is given, that will be used for any newlines in the
  /// output. Otherwise, the line separator will be inferred from the line
  /// endings in the source file.
  ///
  /// If [indent] is given, that many levels of indentation will be prefixed
  /// before each resulting line in the output.
  DartFormatter({this.lineEnding, int pageWidth, this.indent: 0})
      : this.pageWidth = (pageWidth == null) ? 80 : pageWidth;

  /// Formats the given [source] string containing an entire Dart compilation
  /// unit.
  ///
  /// If [uri] is given, it is a [String] or [Uri] used to identify the file
  /// being formatted in error messages.
  String format(String source, {uri}) {
    if (uri == null) {
      uri = "<unknown>";
    } else if (uri is Uri) {
      uri = uri.toString();
    } else if (uri is String) {
      // Do nothing.
    } else {
      throw new ArgumentError("uri must be `null`, a Uri, or a String.");
    }

    return formatSource(
        new SourceCode(source, uri: uri, isCompilationUnit: true)).text;
  }

  /// Formats the given [source] string containing a single Dart statement.
  String formatStatement(String source) {
    return formatSource(new SourceCode(source, isCompilationUnit: false)).text;
  }

  /// Formats the given [source].
  ///
  /// Returns a new [SourceCode] containing the formatted code and the resulting
  /// selection, if any.
  SourceCode formatSource(SourceCode source) {
    var errorListener = new ErrorListener();

    // Tokenize the source.
    var reader = new CharSequenceReader(source.text);
    var stringSource = new StringSource(source.text, source.uri);
    var scanner = new Scanner(stringSource, reader, errorListener);
    var startToken = scanner.tokenize();
    var lineInfo = new LineInfo(scanner.lineStarts);

    // Infer the line ending if not given one. Do it here since now we know
    // where the lines start.
    if (lineEnding == null) {
      // If the first newline is "\r\n", use that. Otherwise, use "\n".
      if (scanner.lineStarts.length > 1 &&
          scanner.lineStarts[1] >= 2 &&
          source.text[scanner.lineStarts[1] - 2] == '\r') {
        lineEnding = "\r\n";
      } else {
        lineEnding = "\n";
      }
    }

    errorListener.throwIfErrors();

    // Parse it.
    var parser = new Parser(stringSource, errorListener);
    parser.parseAsync = true;
    parser.parseEnum = true;

    var node;
    if (source.isCompilationUnit) {
      node = parser.parseCompilationUnit(startToken);
    } else {
      node = parser.parseStatement(startToken);
    }

    errorListener.throwIfErrors();

    // Format it.
    var visitor = new SourceVisitor(this, lineInfo, source);
    return visitor.run(node);
  }
}
