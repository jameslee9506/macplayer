#define MPV_ENABLE_DEPRECATED 0
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#import <mpv/client.h>
#import <mpv/render.h>
#import <mpv/render_gl.h>
#pragma clang diagnostic pop

#import "Features/Thumbnail/FFmpegFrameExtractor.h"

// MARK: - PIPViewController (Private API from PIP.framework)
// Used to host any NSView in a PiP floating window (same approach as IINA).

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PIPViewControllerDelegate;

@interface PIPViewController : NSViewController

@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, weak, nullable) id<PIPViewControllerDelegate> delegate;
@property (nonatomic, weak, nullable) NSWindow *replacementWindow;
@property (nonatomic) NSRect replacementRect;
@property (nonatomic) bool playing;
@property (nonatomic) NSSize aspectRatio;

- (void)presentViewControllerAsPictureInPicture:(NSViewController *)viewController;

@end

@protocol PIPViewControllerDelegate <NSObject>

@optional
- (BOOL)pipShouldClose:(PIPViewController *)pip;
- (void)pipWillClose:(PIPViewController *)pip;
- (void)pipDidClose:(PIPViewController *)pip;
- (void)pipActionPlay:(PIPViewController *)pip;
- (void)pipActionPause:(PIPViewController *)pip;
- (void)pipActionStop:(PIPViewController *)pip;

@end

NS_ASSUME_NONNULL_END
