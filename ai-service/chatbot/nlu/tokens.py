import re
from typing import List, Dict, Optional


class Tokenizer:
    """
    Tokenizer with stemming support for Arabic and English medical text.
    Handles mixed-language input, number extraction, and multi-word terms.
    """

    # Common Arabic prefixes for stemming
    ARABIC_PREFIXES = ["ال", "و", "ف", "ب", "ل", "ك", "س", "ي", "ت", "ا", "ن"]
    # Common Arabic suffixes for stemming
    ARABIC_SUFFIXES = ["ه", "ها", "هم", "هن", "كم", "كن", "نا", "ني", "ي", "ون", "ين", "ات", "ان", "ية"]

    # Common English suffixes for stemming
    ENGLISH_SUFFIXES = ["ing", "ed", "ly", "s", "es", "ies", "ment", "tion", "ness", "able",
                        "ible", "ful", "less", "ist", "ism", "ity", "al", "ial", "ical"]

    def __init__(self):
        # Arabic stop words (medical context)
        self.arabic_stop_words = set([
            "في", "من", "الى", "إلى", "على", "عن", "مع", "كان", "هذا", "هذه",
            "ذلك", "تلك", "هو", "هي", "هم", "ان", "إن", "أن", "قد", "لا",
            "لقد", "لان", "لأن", "ما", "لم", "لن", "كل", "بعض", "هناك",
            "هنا", "ثم", "او", "أو", "ثم", "اذا", "إذا", "عند", "عندما",
            "بين", "تحت", "فوق", "بعد", "قبل", "لدي", "عندي", "غير"
        ])

        self.english_stop_words = set([
            "a", "an", "the", "and", "or", "but", "in", "on", "at", "to",
            "for", "of", "with", "by", "from", "is", "are", "was", "were",
            "be", "been", "being", "have", "has", "had", "do", "does", "did",
            "will", "would", "can", "could", "shall", "should", "may", "might",
            "i", "you", "he", "she", "it", "we", "they", "me", "him", "her",
            "us", "them", "my", "your", "his", "its", "our", "their",
            "this", "that", "these", "those", "up", "down", "out", "off",
            "over", "under", "again", "further", "then", "once", "here",
            "there", "when", "where", "why", "how", "all", "each", "every",
            "both", "few", "more", "most", "other", "some", "such", "no",
            "nor", "not", "only", "own", "same", "so", "than", "too", "very"
        ])

    def tokenize(self, text: str, keep_stop_words: bool = False) -> List[str]:
        """
        Tokenize text into words. Handles Arabic and English.
        Removes punctuation, keeps numbers, handles contractions.
        """
        if not text:
            return []

        # Normalize whitespace
        text = re.sub(r'\s+', ' ', text).strip()

        # Extract tokens (Arabic letters, English letters, numbers)
        tokens = []
        current_token = []

        for char in text:
            if char.isalnum() or char in '_-':
                current_token.append(char)
            elif char.isspace():
                if current_token:
                    token = ''.join(current_token)
                    tokens.append(token)
                    current_token = []
            else:
                # Handle punctuation: consider it a separator
                if current_token:
                    token = ''.join(current_token)
                    tokens.append(token)
                    current_token = []
                # Keep certain punctuation as standalone tokens for intent matching
                if char in '?!' and char:
                    tokens.append(char)

        if current_token:
            token = ''.join(current_token)
            tokens.append(token)

        # Filter stop words unless requested
        if not keep_stop_words:
            tokens = [t for t in tokens if not self._is_stop_word(t)]

        return tokens

    def tokenize_with_positions(self, text: str) -> List[Dict]:
        """
        Tokenize and return tokens with their positions in the original text.
        Useful for entity extraction with span information.
        """
        if not text:
            return []

        tokens = []
        current_token = []
        start_pos = 0

        for i, char in enumerate(text):
            if char.isalnum() or char in '_-':
                if not current_token:
                    start_pos = i
                current_token.append(char)
            else:
                if current_token:
                    token = ''.join(current_token)
                    tokens.append({
                        "text": token,
                        "start": start_pos,
                        "end": i,
                        "is_stop_word": self._is_stop_word(token)
                    })
                    current_token = []
                if not char.isspace() and char not in ' \t\n\r':
                    # Single punctuation
                    tokens.append({
                        "text": char,
                        "start": i,
                        "end": i + 1,
                        "is_stop_word": False,
                        "is_punctuation": True
                    })

        if current_token:
            token = ''.join(current_token)
            tokens.append({
                "text": token,
                "start": start_pos,
                "end": len(text),
                "is_stop_word": self._is_stop_word(token)
            })

        return tokens

    def extract_ngrams(self, tokens: List[str], min_n: int = 1, max_n: int = 3) -> List[str]:
        """
        Extract n-grams from token list.
        Useful for multi-word entity matching (e.g., "chest pain", "طبيب أسنان").
        """
        ngrams = []
        for n in range(min_n, min(max_n + 1, len(tokens) + 1)):
            for i in range(len(tokens) - n + 1):
                ngram = ' '.join(tokens[i:i + n])
                ngrams.append(ngram)
        return ngrams

    def stem_arabic(self, word: str) -> str:
        """
        Simple Arabic stemmer.
        Removes common prefixes and suffixes.
        """
        if not word or len(word) < 3:
            return word

        stem = word

        # Remove definite article "ال"
        if stem.startswith("ال") and len(stem) > 4:
            stem = stem[2:]

        # Remove common prefixes
        for prefix in self.ARABIC_PREFIXES:
            if stem.startswith(prefix) and len(stem) > len(prefix) + 1:
                # Don't strip if it would remove too much
                if len(stem) - len(prefix) >= 2:
                    stem = stem[len(prefix):]
                    break

        # Remove common suffixes
        for suffix in self.ARABIC_SUFFIXES:
            if stem.endswith(suffix) and len(stem) > len(suffix) + 1:
                stem = stem[:-len(suffix)]
                break

        return stem

    def stem_english(self, word: str) -> str:
        """
        Simple English stemmer (Porter-like).
        Removes common suffixes.
        """
        if not word or len(word) < 4:
            return word

        stem = word.lower()

        # Remove common suffixes (order matters for overlap)
        if stem.endswith("ment") and len(stem) > 5:
            stem = stem[:-4]
        elif stem.endswith("tion") and len(stem) > 5:
            stem = stem[:-4]
        elif stem.endswith("ness") and len(stem) > 4:
            stem = stem[:-4]
        elif stem.endswith("able") and len(stem) > 5:
            stem = stem[:-4]
        elif stem.endswith("ible") and len(stem) > 5:
            stem = stem[:-4]
        elif stem.endswith("ful") and len(stem) > 4:
            stem = stem[:-3]
        elif stem.endswith("less") and len(stem) > 5:
            stem = stem[:-4]
        elif stem.endswith("ing") and len(stem) > 4:
            stem = stem[:-3]
            # Handle doubled consonant (running → run)
            if len(stem) >= 2 and stem[-1] == stem[-2]:
                stem = stem[:-1]
        elif stem.endswith("ed") and len(stem) > 4:
            stem = stem[:-2]
            # Handle doubled consonant (stopped → stop)
            if len(stem) >= 2 and stem[-1] == stem[-2]:
                stem = stem[:-1]
        elif stem.endswith("ly") and len(stem) > 4:
            stem = stem[:-2]
        elif stem.endswith("ies") and len(stem) > 4:
            stem = stem[:-3] + "y"
        elif stem.endswith("es") and len(stem) > 4:
            stem = stem[:-2]
        elif stem.endswith("s") and len(stem) > 3 and not stem.endswith("ss"):
            stem = stem[:-1]

        return stem

    def stem(self, word: str, language: str = "auto") -> str:
        """Stem a word based on detected language."""
        if not word:
            return word

        if language == "auto":
            if re.search(r'[\u0600-\u06FF]', word):
                return self.stem_arabic(word)
            return self.stem_english(word)

        if language == "ar":
            return self.stem_arabic(word)
        return self.stem_english(word)

    def extract_numbers(self, text: str) -> List[Dict]:
        """Extract numeric values with context."""
        numbers = []

        # Integer numbers
        for match in re.finditer(r'\d+', text):
            numbers.append({
                "value": int(match.group()),
                "text": match.group(),
                "start": match.start(),
                "end": match.end(),
                "type": "integer"
            })

        # Decimal numbers
        for match in re.finditer(r'\d+\.\d+', text):
            numbers.append({
                "value": float(match.group()),
                "text": match.group(),
                "start": match.start(),
                "end": match.end(),
                "type": "decimal"
            })

        # Ordinal numbers in Arabic (الأول, الثاني, etc.)
        arabic_ordinals = ["اول", "أول", "ثاني", "ثالث", "رابع", "خامس"]
        for ord_str in arabic_ordinals:
            idx = text.find(ord_str)
            if idx >= 0:
                numbers.append({
                    "value": arabic_ordinals.index(ord_str) + 1,
                    "text": ord_str,
                    "start": idx,
                    "end": idx + len(ord_str),
                    "type": "ordinal"
                })

        # English ordinals (first, second, etc.)
        english_ordinals = {
            "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
            "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5
        }
        for ord_str, val in english_ordinals.items():
            idx = text.lower().find(ord_str)
            if idx >= 0:
                numbers.append({
                    "value": val,
                    "text": ord_str,
                    "start": idx,
                    "end": idx + len(ord_str),
                    "type": "ordinal"
                })

        return numbers

    def _is_stop_word(self, word: str) -> bool:
        """Check if a word is a stop word in Arabic or English."""
        word_lower = word.lower()
        return (word_lower in self.english_stop_words) or (word_lower in self.arabic_stop_words)

    def get_word_frequencies(self, tokens: List[str]) -> Dict[str, int]:
        """Count word frequencies in a token list."""
        freq = {}
        for token in tokens:
            token_lower = token.lower()
            freq[token_lower] = freq.get(token_lower, 0) + 1
        return freq