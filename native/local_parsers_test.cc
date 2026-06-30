#include "local_parsers.h"

#include <gtest/gtest.h>

TEST(LocalParsersTest, PdfiumRejectsMissingFile) {
  EXPECT_THROW(ExtractPdfTextWithPdfium("/missing/file.pdf"), std::runtime_error);
}

TEST(LocalParsersTest, TikaRejectsMissingFile) {
  EXPECT_THROW(ExtractDocumentTextWithTika("/missing/file.docx"), std::runtime_error);
}

