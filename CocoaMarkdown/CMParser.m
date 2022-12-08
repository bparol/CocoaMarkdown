//
//  CMParser.m
//  CocoaMarkdown
//
//  Created by Indragie on 1/13/15.
//  Copyright (c) 2015 Indragie Karunaratne. All rights reserved.
//

#import "CMParser.h"
#import "CMDocument.h"
#import "CMIterator.h"
#import "CMNode.h"

#import <libkern/OSAtomic.h>

@interface CMParser ()
@property (atomic, readwrite) CMNode *currentNode;
@property (nonatomic, weak, readwrite) id<CMParserDelegate> delegate;
@end

@implementation CMParser {
    struct {
        unsigned int didStartDocument:1;
        unsigned int didEndDocument:1;
        unsigned int didAbort:1;
        unsigned int foundText:1;
        unsigned int foundHRule:1;
        unsigned int didStartHeader:1;
        unsigned int didEndHeader:1;
        unsigned int didStartParagraph:1;
        unsigned int didEndParagraph:1;
        unsigned int didStartEmphasis:1;
        unsigned int didEndEmphasis:1;
        unsigned int didStartStrong:1;
        unsigned int didEndStrong:1;
        unsigned int didStartLink:1;
        unsigned int didEndLink:1;
        unsigned int didStartImage:1;
        unsigned int didEndImage:1;
        unsigned int foundHTML:1;
        unsigned int foundInlineHTML:1;
        unsigned int foundCodeBlock:1;
        unsigned int foundInlineCode:1;
        unsigned int foundSoftBreak:1;
        unsigned int foundLineBreak:1;
        unsigned int didStartBlockQuote:1;
        unsigned int didEndBlockQuote:1;
        unsigned int didStartUnorderedList:1;
        unsigned int didEndUnorderedList:1;
        unsigned int didStartOrderedList:1;
        unsigned int didEndOrderedList:1;
        unsigned int didStartListItem:1;
        unsigned int didEndListItem:1;
    } _delegateFlags;
    volatile int32_t _parsing;
    
    bool _parsingImage;
    NSString *_linkWithImage;
    NSString *_imageLink;
    NSString *_imageName;
    NSString *_textNestedInImage;
    BOOL _debugEnabled;
}

#pragma mark - Initialization

- (instancetype)initWithDocument:(CMDocument *)document delegate:(id<CMParserDelegate>)delegate debugMode:(BOOL)debugEnabled
{
    NSParameterAssert(document);
    NSParameterAssert(delegate);
    
    if ((self = [super init])) {
        _document = document;
        _debugEnabled = debugEnabled;
        self.delegate = delegate;
    }
    return self;
}

#pragma mark - Parsing

- (void)parse
{
    if (!OSAtomicCompareAndSwap32Barrier(0, 1, &_parsing)) return;
    
    [[_document.rootNode iterator] enumerateUsingBlock:^(CMNode *node, CMEventType event, BOOL *stop) {
        
        if(_debugEnabled){
            NSInteger level = 0;
            NSString *text = @"--";
            if([node parent]) {
                level = 1;
                text = @"----";
            }
            if([[node parent] parent]) {
                level = 2;
                text = @"------";
            }
            else if([[[node parent] parent] parent]) {
                level = 3;
                text = @"--------";
            }
            else if([[[[node parent] parent] parent] parent]) {
                level = 4;
                text = @"----------";
            }
            
            NSString *eventDescription;
            switch (event) {
                case CMEventTypeEnter:
                    eventDescription = @"enter";
                    break;
                case CMEventTypeDone:
                    eventDescription = @"done";
                    break;
                case CMEventTypeExit:
                    eventDescription = @"exit";
                    break;
                case CMEventTypeNone:
                    eventDescription = @"none";
                    break;
            }
            
            NSLog(@"[CocoaMarkdown] %@ type: %ld, event: %@, string: %@, URLString: %@", text, (long)node.type, eventDescription, node.stringValue, node.URLString);
            if(node.stringValue != nil && node.stringValue.length > 0) {
                NSLog(@"[CocoaMarkdown] firstScalar: %hu", [node.stringValue characterAtIndex:0]);
            }
        }
        
        self.currentNode = node;        
        
        if(node.type == CMNodeTypeLink && node.firstChild.type == CMNodeTypeImage && event == CMEventTypeEnter) {
            _parsingImage = true;
            if(node.URLString) {
                _linkWithImage = node.URLString;
            }
        }
        else if(node.type == CMNodeTypeImage && event == CMEventTypeEnter) {
            _parsingImage = true;
            if(node.URLString) {
                _imageLink = node.URLString;
            }
            if(node.title) {
                _imageName = node.title;
            }
        }
        else if(node.type == CMNodeTypeText && _parsingImage) {
            _textNestedInImage = node.stringValue;
        }
        else if(node.type == CMNodeTypeImage && event == CMEventTypeExit) {
            if(node.parent.type != CMNodeTypeLink) {
                NSString *imageDescription = [NSString stringWithFormat: @"![%@](%@ \"%@\")", _textNestedInImage, _imageLink, _imageName];
                [_delegate parser:self foundText:imageDescription];
                
                _parsingImage = false;
                _imageName = nil;
                _imageLink = nil;
            }
        }
        else if(node.type == CMNodeTypeLink && node.firstChild.type == CMNodeTypeImage && _parsingImage) {            
            NSString *imageDescription = [NSString stringWithFormat: @"[![%@](%@)](%@)", _textNestedInImage, _imageLink, _linkWithImage];
            [_delegate parser:self foundText:imageDescription];
            
            _parsingImage = false;
            _imageName = nil;
            _imageLink = nil;
            _linkWithImage = nil;
        }
        else if(!_parsingImage) {
            [self handleNode:node event:event];
        }
        if (_parsing == 0) *stop = YES;
    }];
    
    _parsing = 0;
}

- (void)abortParsing
{
    if (!OSAtomicCompareAndSwap32Barrier(1, 0, &_parsing)) return;
    
    if (_delegateFlags.didAbort) {
        [_delegate parserDidAbort:self];
    }
}

- (void)handleNode:(CMNode *)node event:(CMEventType)event {
    NSAssert((event == CMEventTypeEnter) || (event == CMEventTypeExit), @"Event must be either an exit or enter event");
    
    switch (node.type) {
        case CMNodeTypeDocument:
            if (event == CMEventTypeEnter) {
                if (_delegateFlags.didStartDocument) {
                    [_delegate parserDidStartDocument:self];
                }
            } else if (_delegateFlags.didEndDocument) {
                [_delegate parserDidEndDocument:self];
            }
            break;
        case CMNodeTypeText:
            if (_delegateFlags.foundText) {
                [_delegate parser:self foundText:node.stringValue];
            }
            break;
        case CMNodeTypeHRule:
            if (_delegateFlags.foundHRule) {
                [_delegate parserFoundHRule:self];
            }
            break;
        case CMNodeTypeHeader:
            if (event == CMEventTypeEnter) {
                if (_delegateFlags.didStartHeader) {
                    [_delegate parser:self didStartHeaderWithLevel:node.headerLevel];
                }
            } else if (_delegateFlags.didEndHeader) {
                [_delegate parser:self didEndHeaderWithLevel:node.headerLevel];
            }
            break;
        case CMNodeTypeParagraph:
            if (event == CMEventTypeEnter) {
                if (_delegateFlags.didStartParagraph) {
                    [_delegate parserDidStartParagraph:self];
                }
            } else if (_delegateFlags.didEndParagraph) {
                [_delegate parserDidEndParagraph:self];
            }
            break;
        case CMNodeTypeEmphasis:
            if (event == CMEventTypeEnter) {
                if (_delegateFlags.didStartEmphasis) {
                    [_delegate parserDidStartEmphasis:self];
                }
            } else if (_delegateFlags.didEndEmphasis) {
                [_delegate parserDidEndEmphasis:self];
            }
            break;
        case CMNodeTypeStrong:
            if (event == CMEventTypeEnter) {
                if (_delegateFlags.didStartStrong) {
                    [_delegate parserDidStartStrong:self];
                }
            } else if (_delegateFlags.didEndStrong) {
                [_delegate parserDidEndStrong:self];
            }
            break;
        case CMNodeTypeLink: {
            NSURL *nodeURL = [_document targetURLForNode:node];
            if (event == CMEventTypeEnter) {
                if (_delegateFlags.didStartLink) {
                    [_delegate parser:self didStartLinkWithURL:nodeURL title:node.title];
                }
            } else if (_delegateFlags.didEndLink) {
                [_delegate parser:self didEndLinkWithURL:nodeURL title:node.title];
            }
        }   break;
        case CMNodeTypeImage: {
            NSURL *nodeURL = [_document targetURLForNode:node];
            if (event == CMEventTypeEnter) {
                if (_delegateFlags.didStartImage) {
                    [_delegate parser:self didStartImageWithURL:nodeURL title:node.title];
                }
            } else if (_delegateFlags.didEndImage) {
                [_delegate parser:self didEndImageWithURL:nodeURL title:node.title];
            }
        }   break;
        case CMNodeTypeHTML:
            if (_delegateFlags.foundHTML) {
                [_delegate parser:self foundHTML:node.stringValue];
            }
            break;
        case CMNodeTypeInlineHTML:
            if (_delegateFlags.foundInlineHTML) {
                [_delegate parser:self foundInlineHTML:node.stringValue];
            }
            break;
        case CMNodeTypeCodeBlock:
            if (_delegateFlags.foundCodeBlock) {
                [_delegate parser:self foundCodeBlock:node.stringValue info:node.fencedCodeInfo];
            }
            break;
        case CMNodeTypeCode:
            if (_delegateFlags.foundInlineCode) {
                [_delegate parser:self foundInlineCode:node.stringValue];
            }
            break;
        case CMNodeTypeSoftbreak:
            if (_delegateFlags.foundSoftBreak) {
                //NSLog(@"")
                [_delegate parserFoundSoftBreak:self];
            }
            break;
        case CMNodeTypeLinebreak:
            if (_delegateFlags.foundLineBreak) {
                [_delegate parserFoundLineBreak:self];
            }
            break;
        case CMNodeTypeBlockQuote:
            if (event == CMEventTypeEnter) {
                if (_delegateFlags.didStartBlockQuote) {
                    [_delegate parserDidStartBlockQuote:self];
                }
            } else if (_delegateFlags.didEndBlockQuote) {
                [_delegate parserDidEndBlockQuote:self];
            }
            break;
        case CMNodeTypeList:
            switch (node.listType) {
                case CMListTypeOrdered:
                    if (event == CMEventTypeEnter) {
                        if (_delegateFlags.didStartOrderedList) {
                            [_delegate parser:self didStartOrderedListWithStartingNumber:node.listStartingNumber tight:node.listTight];
                        }
                    } else if (_delegateFlags.didEndOrderedList) {
                        [_delegate parser:self didEndOrderedListWithStartingNumber:node.listStartingNumber tight:node.listTight];
                    }
                    break;
                case CMListTypeUnordered:
                    if (event == CMEventTypeEnter) {
                        if (_delegateFlags.didStartUnorderedList) {
                            [_delegate parser:self didStartUnorderedListWithTightness:node.listTight];
                        }
                    } else if (_delegateFlags.didEndUnorderedList) {
                        [_delegate parser:self didEndUnorderedListWithTightness:node.listTight];
                    }
                    break;
                default:
                    break;
            }
            break;
        case CMNodeTypeItem:
            if (event == CMEventTypeEnter) {
                if (_delegateFlags.didStartListItem) {
                    [_delegate parserDidStartListItem:self];
                }
            } else if (_delegateFlags.didEndListItem) {
                [_delegate parserDidEndListItem:self];
            }
            break;
        default:
            break;
    }
}

#pragma mark - Accessors

- (void)setDelegate:(id<CMParserDelegate>)delegate
{
    if (_delegate != delegate) {
        _delegate = delegate;
        _delegateFlags.didStartDocument = [_delegate respondsToSelector:@selector(parserDidStartDocument:)];
        _delegateFlags.didEndDocument = [_delegate respondsToSelector:@selector(parserDidEndDocument:)];
        _delegateFlags.didAbort = [_delegate respondsToSelector:@selector(parserDidAbort:)];
        _delegateFlags.foundText = [_delegate respondsToSelector:@selector(parser:foundText:)];
        _delegateFlags.foundHRule = [_delegate respondsToSelector:@selector(parserFoundHRule:)];
        _delegateFlags.didStartHeader = [_delegate respondsToSelector:@selector(parser:didStartHeaderWithLevel:)];
        _delegateFlags.didEndHeader = [_delegate respondsToSelector:@selector(parser:didEndHeaderWithLevel:)];
        _delegateFlags.didStartParagraph = [_delegate respondsToSelector:@selector(parserDidStartParagraph:)];
        _delegateFlags.didEndParagraph = [_delegate respondsToSelector:@selector(parserDidEndParagraph:)];
        _delegateFlags.didStartEmphasis = [_delegate respondsToSelector:@selector(parserDidStartEmphasis:)];
        _delegateFlags.didEndEmphasis = [_delegate respondsToSelector:@selector(parserDidEndEmphasis:)];
        _delegateFlags.didStartStrong = [_delegate respondsToSelector:@selector(parserDidStartStrong:)];
        _delegateFlags.didEndStrong = [_delegate respondsToSelector:@selector(parserDidEndStrong:)];
        _delegateFlags.didStartLink = [_delegate respondsToSelector:@selector(parser:didStartLinkWithURL:title:)];
        _delegateFlags.didEndLink = [_delegate respondsToSelector:@selector(parser:didEndLinkWithURL:title:)];
        _delegateFlags.didStartImage = [_delegate respondsToSelector:@selector(parser:didStartImageWithURL:title:)];
        _delegateFlags.didEndImage = [_delegate respondsToSelector:@selector(parser:didEndImageWithURL:title:)];
        _delegateFlags.foundHTML = [_delegate respondsToSelector:@selector(parser:foundHTML:)];
        _delegateFlags.foundInlineHTML = [_delegate respondsToSelector:@selector(parser:foundInlineHTML:)];
        _delegateFlags.foundCodeBlock = [_delegate respondsToSelector:@selector(parser:foundCodeBlock:info:)];
        _delegateFlags.foundInlineCode = [_delegate respondsToSelector:@selector(parser:foundInlineCode:)];
        _delegateFlags.foundSoftBreak = [_delegate respondsToSelector:@selector(parserFoundSoftBreak:)];
        _delegateFlags.foundLineBreak = [_delegate respondsToSelector:@selector(parserFoundLineBreak:)];
        _delegateFlags.didStartBlockQuote = [_delegate respondsToSelector:@selector(parserDidStartBlockQuote:)];
        _delegateFlags.didEndBlockQuote = [_delegate respondsToSelector:@selector(parserDidEndBlockQuote:)];
        _delegateFlags.didStartUnorderedList = [_delegate respondsToSelector:@selector(parser:didStartUnorderedListWithTightness:)];
        _delegateFlags.didEndUnorderedList = [_delegate respondsToSelector:@selector(parser:didEndUnorderedListWithTightness:)];
        _delegateFlags.didStartOrderedList = [_delegate respondsToSelector:@selector(parser:didStartOrderedListWithStartingNumber:tight:)];
        _delegateFlags.didEndOrderedList = [_delegate respondsToSelector:@selector(parser:didEndOrderedListWithStartingNumber:tight:)];
        _delegateFlags.didStartListItem = [_delegate respondsToSelector:@selector(parserDidStartListItem:)];
        _delegateFlags.didEndListItem = [_delegate respondsToSelector:@selector(parserDidEndListItem:)];
    }
}

@end
