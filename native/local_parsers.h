#pragma once

#include <string>

std::string ExtractPdfTextWithPdfium(const std::string& path);
std::string ExtractDocumentTextWithTika(const std::string& path);

