"""
T-050: PDF/OCR Pipeline

Extracts text from PDF files and images.
- PDFs: pdfplumber (text-based) with fallback to pdf2image + Tesseract OCR
- Images: Tesseract OCR via pytesseract

Falls back gracefully if OCR dependencies are not installed.
"""

import io
import os
import logging
from typing import Optional, Tuple

logger = logging.getLogger("medorbit-ai.ocr")


class DocumentExtractor:
    """
    Extracts text from PDF files and images.
    Returns (extracted_text, page_count, method_used).
    """

    SUPPORTED_PDF = {".pdf"}
    SUPPORTED_IMAGE = {".png", ".jpg", ".jpeg", ".tiff", ".tif", ".bmp", ".webp"}

    def extract_from_bytes(
        self,
        file_bytes: bytes,
        file_name: str,
    ) -> dict:
        """
        Main entry point. Dispatches to PDF or image extraction.

        Args:
            file_bytes: Raw file content
            file_name: Original file name (for extension detection)

        Returns:
            {
                "text": str,
                "page_count": int,
                "method": str,  # "pdfplumber" | "ocr" | "tesseract"
                "error": str | None,
            }
        """
        ext = os.path.splitext(file_name)[1].lower()

        if ext in self.SUPPORTED_PDF:
            return self._extract_pdf(file_bytes)
        elif ext in self.SUPPORTED_IMAGE:
            return self._extract_image(file_bytes)
        else:
            return {
                "text": "",
                "page_count": 0,
                "method": "none",
                "error": f"Unsupported file type: {ext}",
            }

    def extract_from_path(self, file_path: str) -> dict:
        """Extract text from a file on disk."""
        ext = os.path.splitext(file_path)[1].lower()

        if ext in self.SUPPORTED_PDF:
            with open(file_path, "rb") as f:
                return self._extract_pdf(f.read())
        elif ext in self.SUPPORTED_IMAGE:
            with open(file_path, "rb") as f:
                return self._extract_image(f.read())
        else:
            return {
                "text": "",
                "page_count": 0,
                "method": "none",
                "error": f"Unsupported file type: {ext}",
            }

    def _extract_pdf(self, file_bytes: bytes) -> dict:
        """Extract text from PDF bytes. Try pdfplumber first, then OCR fallback."""
        # --- Attempt 1: pdfplumber (native text extraction) ---
        try:
            import pdfplumber

            text_parts = []
            page_count = 0

            with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
                page_count = len(pdf.pages)
                for page in pdf.pages:
                    page_text = page.extract_text()
                    if page_text:
                        text_parts.append(page_text.strip())
                    # Also extract tables if present
                    tables = page.extract_tables()
                    for table in tables:
                        for row in table:
                            row_text = " | ".join(cell or "" for cell in row)
                            text_parts.append(row_text)

            full_text = "\n\n".join(text_parts)

            if full_text.strip():
                logger.info("PDF extracted with pdfplumber: %d pages, %d chars", page_count, len(full_text))
                return {
                    "text": full_text,
                    "page_count": page_count,
                    "method": "pdfplumber",
                    "error": None,
                }

            logger.warning("pdfplumber found no text, falling back to OCR")
        except ImportError:
            logger.warning("pdfplumber not installed, trying OCR fallback")

        # --- Attempt 2: OCR fallback via pdf2image + pytesseract ---
        return self._ocr_pdf(file_bytes)

    def _ocr_pdf(self, file_bytes: bytes) -> dict:
        """OCR a PDF by converting pages to images then running Tesseract."""
        try:
            from pdf2image import convert_from_bytes
            import pytesseract
            from PIL import Image

            images = convert_from_bytes(file_bytes, dpi=300)
            page_count = len(images)
            text_parts = []

            for img in images:
                # OCR with Arabic + English support
                ocr_text = pytesseract.image_to_string(
                    img,
                    lang="ara+eng",
                    config="--psm 6",
                )
                if ocr_text.strip():
                    text_parts.append(ocr_text.strip())

            full_text = "\n\n".join(text_parts)
            logger.info("PDF OCR completed: %d pages, %d chars", page_count, len(full_text))

            return {
                "text": full_text,
                "page_count": page_count,
                "method": "ocr",
                "error": None if full_text.strip() else "OCR produced no text",
            }

        except ImportError as e:
            missing = str(e)
            logger.error("OCR dependencies missing: %s", missing)
            return {
                "text": "",
                "page_count": 0,
                "method": "ocr",
                "error": f"OCR dependencies not installed: {missing}. Install pdf2image, pytesseract, and Tesseract OCR.",
            }

    def _extract_image(self, file_bytes: bytes) -> dict:
        """Extract text from image bytes using Tesseract OCR."""
        try:
            import pytesseract
            from PIL import Image

            img = Image.open(io.BytesIO(file_bytes))
            text = pytesseract.image_to_string(img, lang="ara+eng", config="--psm 6")

            logger.info("Image OCR: %d chars extracted", len(text))
            return {
                "text": text.strip(),
                "page_count": 1,
                "method": "tesseract",
                "error": None if text.strip() else "OCR produced no text",
            }

        except ImportError as e:
            logger.error("Image OCR dependencies missing: %s", e)
            return {
                "text": "",
                "page_count": 0,
                "method": "tesseract",
                "error": f"OCR dependencies not installed: {e}",
            }