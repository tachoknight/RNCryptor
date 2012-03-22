//
//  RNOpenSSLCryptor
//
//  Copyright (c) 2012 Rob Napier
//
//  This code is licensed under the MIT License:
//
//  Permission is hereby granted, free of charge, to any person obtaining a 
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//

#import "RNOpenSSLCryptor.h"

const NSUInteger kSaltSize = 8;
NSString * const kSaltedString = @"Salted__";

@interface NSInputStream (RNCryptor)
- (BOOL)_RNGetData:(NSData **)data maxLength:(NSUInteger)maxLength error:(NSError **)error;
@end

@implementation NSInputStream (RNCryptor)
- (BOOL)_RNGetData:(NSData **)data maxLength:(NSUInteger)maxLength error:(NSError **)error
{
  NSMutableData *buffer = [NSMutableData dataWithLength:maxLength];
  if ([self read:buffer.mutableBytes maxLength:maxLength] < 0)
  {
    if (error)
    {
      *error = [self streamError];
      return NO;
    }
  }

  *data = buffer;
  return YES;
}
@end

@interface NSOutputStream (RNCryptor)
- (BOOL)_RNWriteData:(NSData *)data error:(NSError **)error;
@end

@implementation NSOutputStream (RNCryptor)
- (BOOL)_RNWriteData:(NSData *)data error:(NSError **)error
{
  // Writing 0 bytes will close the output stream.
  // This is an undocumented side-effect. radar://9930518
  if (data.length > 0)
  {
    NSInteger bytesWritten = [self write:data.bytes
                               maxLength:data.length];
    if (bytesWritten != data.length)
    {
      if (error)
      {
        *error = [self streamError];
      }
      return NO;
    }
  }
  return YES;
}
@end
@interface RNOpenSSLCryptor ()
@end

@implementation RNOpenSSLCryptor
+ (RNOpenSSLCryptor *)openSSLCryptor
{
  static dispatch_once_t once;
  static id openSSLCryptor = nil;

  dispatch_once(&once, ^{ openSSLCryptor = [[self alloc] init]; });
  return openSSLCryptor;
}

- (NSData *)keyForPassword:(NSString *)password salt:(NSData *)salt
{
  unsigned char md[CC_MD5_DIGEST_LENGTH];
  NSMutableData *keyMaterial = [NSMutableData dataWithData:[password dataUsingEncoding:NSUTF8StringEncoding]];
  [keyMaterial appendData:salt];
  CC_MD5([keyMaterial bytes], [keyMaterial length], md);
  NSData *key = [NSData dataWithBytes:md length:sizeof(md)];
  return key;
}

- (NSData *)IVForKey:(NSData *)key password:(NSString *)password salt:(NSData *)salt
{
  unsigned char md[CC_MD5_DIGEST_LENGTH];
  NSMutableData *IVMaterial = [NSMutableData dataWithData:key];
  [IVMaterial appendData:[password dataUsingEncoding:NSUTF8StringEncoding]];
  [IVMaterial appendData:salt];
  CC_MD5([IVMaterial bytes], [IVMaterial length], md);
  NSData *IV= [NSData dataWithBytes:md length:sizeof(md)];
  return IV;
}

- (BOOL)decryptFromStream:(NSInputStream *)fromStream toStream:(NSOutputStream *)toStream password:(NSString *)password error:(NSError **)error
{
  NSData *salted;
  NSData *encryptionKeySalt;

  [fromStream open];

  if (! [fromStream _RNGetData:&salted maxLength:[kSaltedString length] error:error] ||
      ! [fromStream _RNGetData:&encryptionKeySalt maxLength:kSaltSize error:error])
  {
    return NO;
  }

  if (! [[[NSString alloc] initWithData:salted encoding:NSUTF8StringEncoding] isEqualToString:kSaltedString])
  {
    if (error)
    {
      *error = [NSError errorWithDomain:kRNCryptorErrorDomain code:kRNCyrptorUnknownHeader
                               userInfo:[NSDictionary dictionaryWithObject:NSLocalizedString(@"Could not find salt", @"Unknown header")
                                                                    forKey:NSLocalizedDescriptionKey]];
    }
    return NO;
  }

  NSData *encryptionKey = [self keyForPassword:password salt:encryptionKeySalt];
  NSData *IV = [self IVForKey:encryptionKey password:password salt:encryptionKeySalt];


  RNCryptor *cryptor = [[RNCryptor alloc] initWithSettings:[RNCryptorSettings openSSLSettings]];

  return [cryptor decryptFromStream:fromStream toStream:toStream encryptionKey:encryptionKey IV:IV HMACKey:nil error:error];return NO;
}


//- (BOOL)encryptFromStream:(NSInputStream *)fromStream toStream:(NSOutputStream *)toStream password:(NSString *)password error:(NSError **)error
//{
//  NSData *encryptionKeySalt = [self randomDataOfLength:kSaltSize];
//  NSData *encryptionKey = [self keyForPassword:password salt:encryptionKeySalt];
//
//  NSData *HMACKeySalt = [self randomDataOfLength:self.settings.saltSize];
//  NSData *HMACKey = [self keyForPassword:password salt:HMACKeySalt];
//
//  NSData *IV = [self randomDataOfLength:self.settings.blockSize];
//
//  [output open];
//  uint8_t header[2] = {0, 0};
//  NSData *headerData = [NSData dataWithBytes:header length:sizeof(header)];
//  if (! [output _RNWriteData:headerData error:error] ||
//      ! [output _RNWriteData:encryptionKeySalt error:error] ||
//      ! [output _RNWriteData:HMACKeySalt error:error] ||
//      ! [output _RNWriteData:IV error:error]
//    )
//  {
//    return NO;
//  }
//
//  return [self encryptFromStream:input toStream:output encryptionKey:encryptionKey IV:IV HMACKey:HMACKey error:error];
//
//
//}


@end