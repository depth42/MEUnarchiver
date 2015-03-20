#import "MEUnarchiver.h"

@implementation MEUnarchiver
{
    NSUInteger              _pos;
    int                     _streamerVersion;
    BOOL                    _swap;
    NSMutableArray*         _sharedStrings;
    NSMutableArray*         _sharedObjects;
    NSMutableDictionary*    _classNameMapping;
    NSMutableDictionary*    _versionByClassName;
}

static signed char const Long2Label         = -127;     // 0x81
static signed char const Long4Label         = -126;     // 0x82
static signed char const RealLabel          = -125;     // 0x83
static signed char const NewLabel           = -124;     // 0x84    denotes the start of a new shared string
static signed char const NullLabel          = -123;     // 0x85
static signed char const EndOfObjectLabel   = -122;     // 0x86
static signed char const SmallestLabel      = -110;     // 0x92

#define BIAS(x) (x - SmallestLabel)

- (id)initForReadingWithData:(NSData*)data
{
    NSParameterAssert(data.length > 0);
    
    if(self = [super init])
    {
        _data = [data copy];
        _pos = 0;
        
        if(![self readHeader])
            return nil;
    }
    return self;
}

- (BOOL)isAtEnd
{
    return _pos >= _data.length;
}

- (void)decodeClassName:(NSString*)inArchiveName
            asClassName:(NSString*)trueName
{
    NSParameterAssert(inArchiveName);
    NSParameterAssert(trueName);
    
    if(!_classNameMapping)
        _classNameMapping = [[NSMutableDictionary alloc] init];
    _classNameMapping[inArchiveName] = [trueName copy];
}

- (Class)classForName:(NSString*)className
{
    NSParameterAssert(className);
    
    NSString* replacement = _classNameMapping[className];
    return NSClassFromString(replacement ? replacement : className);
}

- (BOOL)readHeader
{
    signed char streamerVersion;
    if(![self decodeChar:&streamerVersion])
        return NO;
    _streamerVersion = streamerVersion;
    NSAssert(streamerVersion == 4, nil);    // we currently only support v4
    
    NSString* header;
    if(![self decodeString:&header])
        return NO;
    
    BOOL isBig = (NSHostByteOrder() == NS_BigEndian);
    if([header isEqualToString:@"typedstream"])
        _swap = !isBig;
    else if([header isEqualToString:@"streamtyped"])
        _swap = isBig;
    else
        return NO;
    
    int systemVersion;
    if(![self decodeInt:&systemVersion])
        return NO;
    
    return YES;
}

- (BOOL)readObject:(id*)outObject
{
    NSString* string;
    if(![self decodeSharedString:&string])
        return NO;
    if(![string isEqualToString:@"@"])
        return NO;
    
    return [self _readObject:outObject];
}

- (void)registerSharedObject:(id)object
{
    NSParameterAssert(object);
    
    if(!_sharedObjects)
        _sharedObjects = [[NSMutableArray alloc] init];
    [_sharedObjects addObject:object];
}

- (BOOL)_readObject:(id*)outObject
{
    NSParameterAssert(outObject);
    
    signed char ch;
    if(![self decodeChar:&ch])
        return NO;
    
    switch(ch)
    {
        case NullLabel:
            *outObject = nil;
            return YES;
            
        case NewLabel:
        {
            Class class;
            if(![self readClass:&class])
                return NO;
            *outObject = [[class alloc] initWithCoder:self];
            [self registerSharedObject:*outObject];
            
            signed char endMarker;
            if(![self decodeChar:&endMarker] || endMarker != EndOfObjectLabel)
                return NO;
            
            return YES;
        }
            
        default:
        {
            int objectIndex;
            if(![self finishDecodeInt:&objectIndex withChar:ch])
                return NO;
            objectIndex = BIAS(objectIndex);
            if(objectIndex >= _sharedObjects.count)
                return NO;
            *outObject = _sharedObjects[objectIndex];
            return YES;
        }
    }
}

- (BOOL)readClass:(Class*)outClass
{
    NSParameterAssert(outClass);
    
    signed char ch;
    if(![self decodeChar:&ch])
        return NO;
    
    switch(ch)
    {
        case NullLabel:
            *outClass = Nil;
            return YES;
            
        case NewLabel:
        {
            NSString* className;
            if(![self decodeSharedString:&className])
                return NO;
            int version;
            if(![self decodeInt:&version])
                return NO;

            if(!_versionByClassName)
                _versionByClassName = [[NSMutableDictionary alloc] init];
            _versionByClassName[className] = @(version);

            *outClass = [self classForName:className];
            if(!*outClass)
                return NO;
            
            [self registerSharedObject:*outClass];
            
            // We do not check the super-class
            Class superClass;
            if(![self readClass:&superClass])
                return NO;
            
            return YES;
        }
            
        default:
        {
            int objectIndex;
            if(![self finishDecodeInt:&objectIndex withChar:ch])
                return NO;
            objectIndex = BIAS(objectIndex);
            if(objectIndex >= _sharedObjects.count)
                return NO;
            *outClass = _sharedObjects[objectIndex];
            return YES;
        }
    }
    
}

- (BOOL)readBytes:(void*)bytes length:(NSUInteger)length
{
    if(_pos + length > _data.length)
        return NO;
    [_data getBytes:bytes range:NSMakeRange(_pos, length)];
    _pos += length;
    return YES;
}

- (BOOL)decodeChar:(signed char*)outChar
{
    NSParameterAssert(outChar);
    return [self readBytes:outChar length:1];
}

- (BOOL)decodeFloat:(float*)outFloat
{
    NSParameterAssert(outFloat);
    
    signed char charValue;
    if(![self decodeChar:&charValue])
        return NO;
    if(charValue != RealLabel)
    {
        int intValue;
        if(![self finishDecodeInt:&intValue withChar:charValue])
            return NO;
        *outFloat = intValue;
        return YES;
    }
    NSSwappedFloat value;
    if(![self readBytes:&value length:sizeof(NSSwappedFloat)])
        return NO;
    
    *outFloat = [self swappedFloat:value];
    
    return YES;
}

- (BOOL)decodeDouble:(double*)outDouble
{
    NSParameterAssert(outDouble);
    
    signed char charValue;
    if(![self decodeChar:&charValue])
        return NO;
    if(charValue != RealLabel)
    {
        int intValue;
        if(![self finishDecodeInt:&intValue withChar:charValue])
            return NO;
        *outDouble = intValue;
        return YES;
    }
    NSSwappedDouble value;
    if(![self readBytes:&value length:sizeof(NSSwappedDouble)])
        return NO;
    
    *outDouble = [self swappedDouble:value];
    return YES;
}

- (BOOL)decodeString:(NSString**)outString
{
    NSParameterAssert(outString);
    
    signed char charValue;
    if(![self decodeChar:&charValue])
        return NO;
    
    if(charValue == NullLabel)
    {
        *outString = nil;
        return YES;
    }
    
    int length;
    if(![self finishDecodeInt:&length
                     withChar:charValue])
        return NO;
    if(length <= 0)
        return NO;
    
    char bytes[length];
    if(![self readBytes:bytes length:length])
        return NO;
    *outString = [[NSString alloc] initWithBytes:bytes
                                          length:length
                                        encoding:NSUTF8StringEncoding];
    return YES;
}

- (BOOL)decodeSharedString:(NSString**)outString
{
    signed char ch;
    if(![self decodeChar:&ch])
        return NO;
    if(ch == NullLabel)
    {
        *outString = nil;
        return YES;
    }
    if(ch == NewLabel)
    {
        if(![self decodeString:outString])
            return NO;
        if(!_sharedStrings)
            _sharedStrings = [[NSMutableArray alloc] init];
        [_sharedStrings addObject:*outString];
    }
    else
    {
        int stringIndex;
        if(![self finishDecodeInt:&stringIndex
                         withChar:ch])
            return NO;
        stringIndex = BIAS(stringIndex);
        if(stringIndex >= _sharedStrings.count)
            return NO;
        *outString = _sharedStrings[stringIndex];
    }
    return YES;
}

- (BOOL)decodeShort:(short*)outShort
{
    NSParameterAssert(outShort);
    
    signed char ch;
    if(![self decodeChar:&ch])
        return NO;
    
    if(ch != Long2Label)
    {
        *outShort = ch;
        return YES;
    }
    
    short value;
    if(![self readBytes:&value length:2])
        return NO;
    
    *outShort = [self swappedShort:value];
    
    return YES;
}

- (BOOL)decodeInt:(int*)outInt
{
    NSParameterAssert(outInt);
    signed char ch;
    if(![self decodeChar:&ch])
        return NO;
    return [self finishDecodeInt:outInt withChar:ch];
}

- (BOOL)finishDecodeInt:(int*)outInt
               withChar:(signed char)charValue
{
    NSParameterAssert(outInt);
    
    switch(charValue)
    {
        case Long2Label:
        {
            short value;
            if(![self readBytes:&value length:2])
                return NO;
            *outInt = [self swappedShort:value];
            break;
        }
            
        case Long4Label:
        {
            int value;
            if(![self readBytes:&value length:4])
                return NO;
            *outInt = [self swappedInt:value];
            break;
        }
            
        default:
            *outInt = charValue;
            break;
    }
    return YES;
}

- (unsigned short)swappedShort:(unsigned short)value
{
    return _swap ? NSSwapShort(value) : value;
}

- (unsigned int)swappedInt:(unsigned int)value
{
    return _swap ? NSSwapInt(value) : value;
}

- (unsigned long long)swappedLongLong:(unsigned long long)value
{
    return _swap ? NSSwapLongLong(value) : value;
}

- (float)swappedFloat:(NSSwappedFloat)value
{
    return _swap ? NSConvertSwappedFloatToHost(NSSwapFloat(value)) : NSConvertSwappedFloatToHost(value);
}

- (double)swappedDouble:(NSSwappedDouble)value
{
    return _swap ? NSConvertSwappedDoubleToHost(NSSwapDouble(value)) : NSConvertSwappedDoubleToHost(value);
}

- (BOOL)readType:(const char*)type data:(void*)data
{
    NSParameterAssert(type);
    NSParameterAssert(data);
    
    NSString* string;
    if(![self decodeSharedString:&string] || string.length == 0)
        return NO;
    
    const char* str = string.UTF8String;
    if(strcmp(str, type) != 0)
    {
        NSLog(@"wrong type in archive '%s', expected '%s'", str, type);
        return NO;
    }
    
    char ch = str[0];
    
    switch(ch)
    {
        case 'c':
        case 'C':
        {
            signed char value;
            if(![self decodeChar:&value])
                return NO;
            *((char*)data) = (char)value;
            break;
        }
            
        case 's':
        case 'S':
        {
            short value;
            if(![self decodeShort:&value])
                return NO;
            *((short*)data) = value;
            break;
        }
            
        case 'i':
        case 'I':
        case 'l':
        case 'L':
        {
            int value;
            if(![self decodeInt:&value])
                return NO;
            *((int*)data) = value;
            break;
        }
            
        case 'f':
        {
            float value;
            if(![self decodeFloat:&value])
                return NO;
            *((float*)data) = value;
            break;
        }
            
        case 'd':
        {
            double value;
            if(![self decodeDouble:&value])
                return NO;
            *((double*)data) = value;
            break;
        }
            
        default:
            NSLog(@"unsupported archiving type %c", ch);
            return NO;
    }
    return YES;
}


#pragma mark - Convenience Methods

+ (id) compatibilityUnarchiveObjectWithData:(NSData*)data
                            decodeClassName:(NSString*)archiveClassName
                                asClassName:(NSString*)className
{
    NSParameterAssert(!archiveClassName || className);
    
    if(!data)
        return nil;
    
#if UXTARGET_IOS
    MEUnarchiver* unarchiver = [[MEUnarchiver alloc] initForReadingWithData:data];
    if(archiveClassName)
        [unarchiver decodeClassName:archiveClassName asClassName:className];
    return [unarchiver decodeObject];
#else
    NSUnarchiver* unarchiver = [[NSUnarchiver alloc] initForReadingWithData:data];
    if(archiveClassName)
        [unarchiver decodeClassName:archiveClassName asClassName:className];
    return [unarchiver decodeObject];
#endif
}

#pragma mark - NSCoder methods

- (void)decodeValueOfObjCType:(const char*)type at:(void*)data
{
    NSParameterAssert(type);
    NSParameterAssert(data);
    
    // Make sure that even under iOS BOOLs are read with 'c' type.
    if(strcmp(type, @encode(BOOL)) == 0)
        type = "c";
    
    [self readType:type data:data];
}

- (id)decodeObject
{
    id obj;
    [self readObject:&obj];
    return obj;
}

- (NSInteger)versionForClassName:(NSString *)className
{
    NSParameterAssert(className);
    return ((NSNumber*)_versionByClassName[className]).integerValue;
}

@end
