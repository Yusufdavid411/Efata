class PasswordStrengthResult {
  const PasswordStrengthResult({
    required this.score,
    required this.label,
    required this.feedback,
    required this.passedRules,
    required this.isAcceptable,
  });

  final int score;
  final String label;
  final List<String> feedback;
  final Set<PasswordRule> passedRules;
  final bool isAcceptable;
}

enum PasswordRule {
  length,
  mixedCharacters,
  notOnlyLetters,
  notOnlyNumbers,
  noObviousWords,
  passwordsMatch,
}

class PasswordStrengthService {
  PasswordStrengthService._();

  static const commonWeakTerms = {
    'password',
    'qwerty',
    '123456',
    '12345678',
    '123456789',
    '111111',
    '000000',
    'abcdef',
    'welcome',
    'iloveyou',
    'admin',
    'letmein',
  };

  static PasswordStrengthResult evaluate({
    required String password,
    required String confirmPassword,
    required String email,
  }) {
    final passed = <PasswordRule>{};
    final feedback = <String>[];
    final trimmedEmailName = email.split('@').first.toLowerCase();
    final lower = password.toLowerCase();
    final uniqueCharacters = password.split('').toSet().length;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'\d').hasMatch(password);
    final hasSymbolOrSpace = RegExp(r'[^A-Za-z0-9]').hasMatch(password);

    if (password.length >= 8) {
      passed.add(PasswordRule.length);
    } else {
      feedback.add('Use at least 8 characters.');
    }

    if ((hasLetter && hasNumber) || (hasLetter && hasSymbolOrSpace)) {
      passed.add(PasswordRule.mixedCharacters);
    } else {
      feedback.add('Mix letters with numbers, spaces, or symbols.');
    }

    if (!RegExp(r'^[A-Za-z]+$').hasMatch(password)) {
      passed.add(PasswordRule.notOnlyLetters);
    } else {
      feedback.add('Do not use only alphabet letters.');
    }

    if (!RegExp(r'^\d+$').hasMatch(password)) {
      passed.add(PasswordRule.notOnlyNumbers);
    } else {
      feedback.add('Do not use only numbers.');
    }

    final containsWeakTerm =
        commonWeakTerms.any(lower.contains) ||
        (trimmedEmailName.length >= 3 && lower.contains(trimmedEmailName)) ||
        uniqueCharacters <= 3;

    if (!containsWeakTerm) {
      passed.add(PasswordRule.noObviousWords);
    } else {
      feedback.add('Choose a less predictable password without your email.');
    }

    if (password.isNotEmpty && password == confirmPassword) {
      passed.add(PasswordRule.passwordsMatch);
    } else {
      feedback.add('Both passwords must match.');
    }

    final baseScore = [
      PasswordRule.length,
      PasswordRule.mixedCharacters,
      PasswordRule.notOnlyLetters,
      PasswordRule.notOnlyNumbers,
      PasswordRule.noObviousWords,
    ].where(passed.contains).length;

    final label = switch (baseScore) {
      <= 2 => 'Weak',
      3 || 4 => 'Fair',
      _ => 'Strong',
    };

    final isAcceptable =
        passed.contains(PasswordRule.length) &&
        passed.contains(PasswordRule.mixedCharacters) &&
        passed.contains(PasswordRule.notOnlyLetters) &&
        passed.contains(PasswordRule.notOnlyNumbers) &&
        passed.contains(PasswordRule.noObviousWords) &&
        passed.contains(PasswordRule.passwordsMatch);

    return PasswordStrengthResult(
      score: baseScore,
      label: label,
      feedback: feedback,
      passedRules: passed,
      isAcceptable: isAcceptable,
    );
  }
}
