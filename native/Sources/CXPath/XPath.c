#include "UtataneXPath.h"
#include <libxml/parser.h>
#include <libxml/xpath.h>
#include <stdio.h>

static xmlParserInputPtr reject_entity(void *context, const xmlChar *public_id, const xmlChar *system_id) {
    (void)context; (void)public_id; (void)system_id;
    return NULL;
}

static void reject_doctype(void *context, const xmlChar *name, const xmlChar *external_id, const xmlChar *system_id) {
    (void)name; (void)external_id; (void)system_id;
    xmlStopParser((xmlParserCtxtPtr)context);
}

void *utatane_xpath_open(const char *bytes, int32_t length) {
    if (!bytes || length <= 0 || length > 8 * 1024 * 1024) return NULL;
    xmlParserCtxtPtr parser = xmlNewParserCtxt();
    if (!parser) return NULL;
    parser->sax->resolveEntity = reject_entity;
    parser->sax->internalSubset = reject_doctype;
    parser->sax->externalSubset = reject_doctype;
    parser->replaceEntities = 0;
    parser->loadsubset = 0;
    xmlDocPtr doc = xmlCtxtReadMemory(parser, bytes, length, NULL, NULL,
        XML_PARSE_NONET | XML_PARSE_NOERROR | XML_PARSE_NOWARNING);
    xmlFreeParserCtxt(parser);
    // Do not load DTDs, expand entities or process XInclude. Reject DTD-bearing
    // documents before any node contents are materialized by the XPath layer.
    if (doc && (doc->intSubset || doc->extSubset || !xmlDocGetRootElement(doc))) {
        xmlFreeDoc(doc); return NULL;
    }
    return doc;
}

void utatane_xpath_close(void *doc) { if (doc) xmlFreeDoc(doc); }

static void ignore_error(void *context, xmlErrorPtr error) { (void)context; (void)error; }

static int emit(xmlChar *text, void *context, UtataneXPathValue value) {
    if (!text) return 0;
    int result = value(context, (const char *)text, (size_t)xmlStrlen(text));
    xmlFree(text);
    return result;
}

int32_t utatane_xpath_get(void *document, const char *expression, int32_t *nodes,
                         void *context, UtataneXPathValue value) {
    if (!document || !expression || !nodes || !value) return 0;
    xmlXPathContextPtr xpath = xmlXPathNewContext(document);
    if (!xpath) return 0;
    xpath->node = xmlDocGetRootElement(document);
    xpath->error = ignore_error;
    // Apple's libxml2 exposes these limits on macOS 13 and later. Our floor is 14.
    xpath->opLimit = 1000000;
    xmlXPathObjectPtr result = xmlXPathEvalExpression((const xmlChar *)expression, xpath);
    int success = result != NULL;
    *nodes = result && result->type == XPATH_NODESET;
    if (success && *nodes) {
        xmlNodeSetPtr set = result->nodesetval;
        if (set && set->nodeNr > 8192) success = 0;
        for (int i = 0; success && set && i < set->nodeNr; ++i) {
            xmlNodePtr node = set->nodeTab[i];
            if (node->type == XML_ATTRIBUTE_NODE || node->type == XML_TEXT_NODE || node->type == XML_CDATA_SECTION_NODE) {
                success = emit(xmlNodeGetContent(node), context, value);
            } else if (node->type == XML_ELEMENT_NODE && node->children && node->children == node->last &&
                       (node->children->type == XML_TEXT_NODE || node->children->type == XML_CDATA_SECTION_NODE) &&
                       node->children->content && xmlStrlen(node->children->content)) {
                success = emit(xmlNodeGetContent(node->children), context, value);
            }
        }
    } else if (success && result->type == XPATH_BOOLEAN) {
        const char *text = result->boolval ? "1" : "0";
        success = value(context, text, 1);
    } else if (success && result->type == XPATH_NUMBER) {
        char text[128];
        int length = snprintf(text, sizeof(text), "%.6g", result->floatval);
        success = length > 0 && length < (int)sizeof(text) && value(context, text, (size_t)length);
    } else if (success && result->type == XPATH_STRING) {
        success = value(context, (const char *)result->stringval, (size_t)xmlStrlen(result->stringval));
    } else if (success) success = 0;
    if (result) xmlXPathFreeObject(result);
    xmlXPathFreeContext(xpath);
    return success;
}
