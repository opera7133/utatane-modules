#ifndef UTATANE_XPATH_H
#define UTATANE_XPATH_H
#include <stddef.h>
#include <stdint.h>
typedef int32_t (*UtataneXPathValue)(void *, const char *, size_t);
void *utatane_xpath_open(const char *, int32_t);
void utatane_xpath_close(void *);
int32_t utatane_xpath_get(void *, const char *, int32_t *, void *, UtataneXPathValue);
#endif
