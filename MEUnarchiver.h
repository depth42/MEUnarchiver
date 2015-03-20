// Replacement for the NSUnarchiver which is only available as private API under iOS.
// We need it for importing documents of Merlin 2 which used NSArchiver for serializing values
// for durations, utilizations, budgets etc. For maximum compatibility, we should still prefer to
// to use the original NSArchiver under OS X.
// The implementation is loosely based on file format documented by the code found in typedstream.m inside objc-1.tar.gz of an old Darwin release
// http://ia700409.us.archive.org/zipview.php?zip=/12/items/ftp_nextstuff_info/nextstuff.info.2012.11.zip
// http://archive.org/download/ftp_nextstuff_info/nextstuff.info.2012.11.zip/nextstuff.info%2Fmirrors%2Fotto%2Fhtml%2Fpub%2FDarwin%2FPublicSource%2FDarwin%2Fobjc-1.tar.gz


@interface MEUnarchiver : NSCoder

- (id)initForReadingWithData:(NSData*)data;

@property (nonatomic, readonly, copy)   NSData* data;
@property (nonatomic, readonly)         BOOL    isAtEnd;

- (void)decodeClassName:(NSString*)inArchiveName
            asClassName:(NSString*)trueName;

- (void)decodeValueOfObjCType:(const char*)type at:(void*)data;

- (id)decodeObject;

// Uses NSArchiver under OS X and MEArchiver under iOS.
+ (id) compatibilityUnarchiveObjectWithData:(NSData*)data
                            decodeClassName:(NSString*)archiveClassName
                                asClassName:(NSString*)className;

@end
