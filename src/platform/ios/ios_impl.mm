#import "ios_impl.h"

#import <AVFAudio/AVFAudio.h>
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>

#include <atomic>
#include <stdlib.h>
#include <unistd.h>

namespace {

constexpr uint32_t kButtonB = 1u << 0;
constexpr uint32_t kButtonY = 1u << 1;
constexpr uint32_t kButtonSelect = 1u << 2;
constexpr uint32_t kButtonStart = 1u << 3;
constexpr uint32_t kButtonUp = 1u << 4;
constexpr uint32_t kButtonDown = 1u << 5;
constexpr uint32_t kButtonLeft = 1u << 6;
constexpr uint32_t kButtonRight = 1u << 7;
constexpr uint32_t kButtonA = 1u << 8;
constexpr uint32_t kButtonX = 1u << 9;
constexpr uint32_t kButtonL = 1u << 10;
constexpr uint32_t kButtonR = 1u << 11;
constexpr uint32_t kDpadMask = kButtonUp | kButtonDown | kButtonLeft | kButtonRight;

std::atomic<uint32_t> gTouchInput{0};
std::atomic<bool> gControllerConnected{false};
std::atomic<uint32_t> gPendingActions{0};

NSString *const kOpacityKey = @"SMW.TouchControls.opacity";
NSString *const kScaleKey = @"SMW.TouchControls.scale";
NSString *const kAutoHideKey = @"SMW.TouchControls.autoHide";

void SetInputMask(uint32_t mask, bool pressed) {
  if (pressed)
    gTouchInput.fetch_or(mask, std::memory_order_relaxed);
  else
    gTouchInput.fetch_and(~mask, std::memory_order_relaxed);
}

UIWindow *ActiveWindow(void) {
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (scene.activationState != UISceneActivationStateUnattached &&
        [scene isKindOfClass:UIWindowScene.class]) {
      for (UIWindow *window in ((UIWindowScene *)scene).windows) {
        if (window.isKeyWindow)
          return window;
      }
    }
  }
  return nil;
}

UIColor *ControlFill(void) {
  return [UIColor colorWithWhite:0.04 alpha:0.38];
}

UIColor *PressedFill(UIColor *tint) {
  return [tint colorWithAlphaComponent:0.82];
}

}  // namespace

@interface SMWTouchButton : UIButton
@property(nonatomic) uint32_t inputMask;
@property(nonatomic, strong) UIColor *accentColor;
@end

@implementation SMWTouchButton {
  UIImpactFeedbackGenerator *_feedback;
}

- (instancetype)initWithLabel:(NSString *)label
                         mask:(uint32_t)mask
                       accent:(UIColor *)accent
          accessibilityLabel:(NSString *)accessibilityLabel {
  self = [super initWithFrame:CGRectZero];
  if (self) {
    _inputMask = mask;
    _accentColor = accent;
    _feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    self.accessibilityLabel = accessibilityLabel;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.exclusiveTouch = NO;
    self.multipleTouchEnabled = NO;
    self.backgroundColor = ControlFill();
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.62].CGColor;
    self.layer.borderWidth = 1.5;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.32;
    self.layer.shadowOffset = CGSizeMake(0.0, 3.0);
    self.layer.shadowRadius = 5.0;
    self.titleLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightBold];
    [self setTitle:label forState:UIControlStateNormal];
    [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(released)
           forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                            UIControlEventTouchCancel];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  self.layer.cornerRadius = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds)) * 0.5;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat height = CGRectGetHeight(self.bounds);
  if (fabs(width - height) < 0.5) {
    CGFloat radius = width * 0.5;
    CGFloat dx = point.x - radius;
    CGFloat dy = point.y - radius;
    return dx * dx + dy * dy <= radius * radius;
  }
  return [super pointInside:point withEvent:event];
}

- (void)pressed {
  SetInputMask(self.inputMask, true);
  self.backgroundColor = PressedFill(self.accentColor);
  self.transform = CGAffineTransformMakeScale(0.94, 0.94);
  [_feedback impactOccurredWithIntensity:0.65];
  [_feedback prepare];
}

- (void)released {
  SetInputMask(self.inputMask, false);
  self.backgroundColor = ControlFill();
  self.transform = CGAffineTransformIdentity;
}

- (void)forceRelease {
  [self released];
}

@end

@interface SMWDpadView : UIView
- (void)forceRelease;
@end

@implementation SMWDpadView {
  uint32_t _activeMask;
  UIImpactFeedbackGenerator *_feedback;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.clearColor;
    self.multipleTouchEnabled = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Directional pad";
    self.accessibilityHint = @"Slide from the center to move Mario";
    _feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
  }
  return self;
}

- (void)drawRect:(CGRect)rect {
  CGContextRef context = UIGraphicsGetCurrentContext();
  CGFloat width = CGRectGetWidth(self.bounds);
  CGFloat arm = width * 0.36;
  CGFloat inner = (width - arm) * 0.5;
  CGFloat outer = inner + arm;
  UIBezierPath *path = [UIBezierPath bezierPath];
  [path moveToPoint:CGPointMake(inner, 0.0)];
  [path addLineToPoint:CGPointMake(outer, 0.0)];
  [path addLineToPoint:CGPointMake(outer, inner)];
  [path addLineToPoint:CGPointMake(width, inner)];
  [path addLineToPoint:CGPointMake(width, outer)];
  [path addLineToPoint:CGPointMake(outer, outer)];
  [path addLineToPoint:CGPointMake(outer, width)];
  [path addLineToPoint:CGPointMake(inner, width)];
  [path addLineToPoint:CGPointMake(inner, outer)];
  [path addLineToPoint:CGPointMake(0.0, outer)];
  [path addLineToPoint:CGPointMake(0.0, inner)];
  [path addLineToPoint:CGPointMake(inner, inner)];
  [path closePath];
  CGContextAddPath(context, path.CGPath);
  CGContextSetFillColorWithColor(context, ControlFill().CGColor);
  CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:1.0 alpha:0.62].CGColor);
  CGContextSetLineWidth(context, 1.5);
  CGContextSetLineJoin(context, kCGLineJoinRound);
  CGContextDrawPath(context, kCGPathFillStroke);

  CGPoint center = CGPointMake(width * 0.5, width * 0.5);
  CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1.0 alpha:0.22].CGColor);
  CGContextFillEllipseInRect(context, CGRectMake(center.x - arm * 0.17, center.y - arm * 0.17,
                                                  arm * 0.34, arm * 0.34));

  CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1.0 alpha:0.64].CGColor);
  CGFloat arrow = arm * 0.18;
  CGFloat offset = width * 0.27;
  CGContextMoveToPoint(context, center.x, center.y - offset - arrow);
  CGContextAddLineToPoint(context, center.x - arrow, center.y - offset + arrow);
  CGContextAddLineToPoint(context, center.x + arrow, center.y - offset + arrow);
  CGContextClosePath(context);
  CGContextMoveToPoint(context, center.x, center.y + offset + arrow);
  CGContextAddLineToPoint(context, center.x - arrow, center.y + offset - arrow);
  CGContextAddLineToPoint(context, center.x + arrow, center.y + offset - arrow);
  CGContextClosePath(context);
  CGContextMoveToPoint(context, center.x - offset - arrow, center.y);
  CGContextAddLineToPoint(context, center.x - offset + arrow, center.y - arrow);
  CGContextAddLineToPoint(context, center.x - offset + arrow, center.y + arrow);
  CGContextClosePath(context);
  CGContextMoveToPoint(context, center.x + offset + arrow, center.y);
  CGContextAddLineToPoint(context, center.x + offset - arrow, center.y - arrow);
  CGContextAddLineToPoint(context, center.x + offset - arrow, center.y + arrow);
  CGContextClosePath(context);
  CGContextFillPath(context);
}

- (uint32_t)maskAtPoint:(CGPoint)point {
  CGFloat width = CGRectGetWidth(self.bounds);
  CGPoint delta = CGPointMake(point.x - width * 0.5, point.y - width * 0.5);
  CGFloat engage = width * 0.12;
  uint32_t mask = 0;
  if (delta.x < -engage)
    mask |= kButtonLeft;
  else if (delta.x > engage)
    mask |= kButtonRight;
  if (delta.y < -engage)
    mask |= kButtonUp;
  else if (delta.y > engage)
    mask |= kButtonDown;
  return mask;
}

- (void)updateWithTouch:(UITouch *)touch {
  uint32_t nextMask = [self maskAtPoint:[touch locationInView:self]];
  if (nextMask == _activeMask)
    return;
  SetInputMask(_activeMask & ~nextMask, false);
  SetInputMask(nextMask & ~_activeMask, true);
  if (nextMask != 0 && _activeMask == 0) {
    [_feedback impactOccurredWithIntensity:0.55];
    [_feedback prepare];
  }
  _activeMask = nextMask;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self updateWithTouch:touches.anyObject];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self updateWithTouch:touches.anyObject];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self forceRelease];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [self forceRelease];
}

- (void)forceRelease {
  SetInputMask(kDpadMask, false);
  _activeMask = 0;
}

@end

@class SMWTouchOverlay;

@interface SMWControlSettings : UIVisualEffectView
@property(nonatomic, weak) SMWTouchOverlay *overlay;
@end

@interface SMWTouchOverlay : UIView
@property(nonatomic, readonly) SMWTouchButton *menuButton;
- (void)applyPreferences;
- (void)setControlOpacity:(CGFloat)opacity;
- (void)setControlScale:(CGFloat)scale;
- (void)setAutoHideEnabled:(BOOL)enabled;
- (void)settingsDidClose;
- (void)requestAction:(uint32_t)action;
- (void)openSettings;
- (void)releaseAll;
- (void)setControllerConnected:(BOOL)connected;
@end

@implementation SMWControlSettings {
  UISlider *_opacitySlider;
  UISlider *_scaleSlider;
  UILabel *_opacityValue;
  UILabel *_scaleValue;
  UISegmentedControl *_visibilityControl;
  UIStackView *_actions;
  UIStackView *_confirmationRow;
  UILabel *_confirmationLabel;
  UIButton *_confirmationButton;
  uint32_t _confirmationAction;
}

- (instancetype)initWithEffect:(UIVisualEffect *)effect {
  self = [super initWithEffect:effect];
  if (self) {
    self.layer.cornerRadius = 20.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;

    UILabel *title = [[UILabel alloc] init];
    title.text = @"GAME MENU";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Resume" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    done.accessibilityHint = @"Close the menu and restore gameplay controls";
    [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[ title, done ]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.distribution = UIStackViewDistributionEqualSpacing;

    UIButton *save = [self actionButton:@"Save" selector:@selector(saveState)];
    UIButton *load = [self actionButton:@"Load" selector:@selector(loadState)];
    UIButton *reset = [self actionButton:@"Reset" selector:@selector(resetGame)];
    UIButton *quit = [self actionButton:@"Quit" selector:@selector(quitGame)];
    quit.tintColor = [UIColor colorWithRed:1.0 green:0.42 blue:0.38 alpha:1.0];
    _actions =
        [[UIStackView alloc] initWithArrangedSubviews:@[ save, load, reset, quit ]];
    _actions.axis = UILayoutConstraintAxisHorizontal;
    _actions.spacing = 8.0;
    _actions.distribution = UIStackViewDistributionFillEqually;
    NSLayoutConstraint *actionsHeight = [_actions.heightAnchor constraintEqualToConstant:38.0];
    actionsHeight.priority = UILayoutPriorityRequired - 1.0;
    actionsHeight.active = YES;

    _confirmationLabel = [self label:@""];
    _confirmationLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    UIButton *cancel = [self actionButton:@"Cancel" selector:@selector(cancelConfirmation)];
    _confirmationButton =
        [self actionButton:@"Confirm" selector:@selector(confirmPendingAction)];
    [cancel.widthAnchor constraintEqualToConstant:72.0].active = YES;
    [_confirmationButton.widthAnchor constraintEqualToConstant:88.0].active = YES;
    _confirmationRow = [[UIStackView alloc]
        initWithArrangedSubviews:@[ _confirmationLabel, cancel, _confirmationButton ]];
    _confirmationRow.axis = UILayoutConstraintAxisHorizontal;
    _confirmationRow.alignment = UIStackViewAlignmentFill;
    _confirmationRow.spacing = 8.0;
    NSLayoutConstraint *confirmationHeight =
        [_confirmationRow.heightAnchor constraintEqualToConstant:38.0];
    confirmationHeight.priority = UILayoutPriorityRequired - 1.0;
    confirmationHeight.active = YES;
    _confirmationRow.hidden = YES;

    UILabel *opacityLabel = [self label:@"Opacity"];
    _opacitySlider = [[UISlider alloc] init];
    _opacitySlider.minimumValue = 0.0;
    _opacitySlider.maximumValue = 1.0;
    _opacitySlider.accessibilityLabel = @"Touch control opacity";
    [_opacitySlider addTarget:self action:@selector(opacityChanged)
             forControlEvents:UIControlEventValueChanged];
    [_opacitySlider addTarget:self action:@selector(persistSliders)
             forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                              UIControlEventTouchCancel];
    _opacityValue = [self valueLabel];

    UILabel *scaleLabel = [self label:@"Control size"];
    _scaleSlider = [[UISlider alloc] init];
    _scaleSlider.minimumValue = 0.8;
    _scaleSlider.maximumValue = 1.25;
    _scaleSlider.accessibilityLabel = @"Touch control size";
    [_scaleSlider addTarget:self action:@selector(scaleChanged)
           forControlEvents:UIControlEventValueChanged];
    [_scaleSlider addTarget:self action:@selector(persistSliders)
           forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                            UIControlEventTouchCancel];
    _scaleValue = [self valueLabel];

    UILabel *visibilityLabel = [self label:@"Touch controls"];
    _visibilityControl =
        [[UISegmentedControl alloc] initWithItems:@[ @"Always", @"Auto-hide" ]];
    _visibilityControl.accessibilityLabel = @"Touch control visibility";
    _visibilityControl.accessibilityHint =
        @"Auto-hide removes gameplay controls only while a physical controller is connected";
    [_visibilityControl addTarget:self action:@selector(visibilityChanged)
                 forControlEvents:UIControlEventValueChanged];

    UIStackView *opacityRow =
        [self sliderRowWithLabel:opacityLabel slider:_opacitySlider value:_opacityValue];
    UIStackView *scaleRow =
        [self sliderRowWithLabel:scaleLabel slider:_scaleSlider value:_scaleValue];
    UIStackView *visibilityRow =
        [self rowWithLabel:visibilityLabel control:_visibilityControl controlWidth:172.0];
    UIStackView *stack = [[UIStackView alloc]
        initWithArrangedSubviews:@[
          header, _actions, _confirmationRow, opacityRow, scaleRow, visibilityRow
        ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
      [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
      [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],
      [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16.0],
      [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14.0],
    ]];
  }
  return self;
}

- (UILabel *)label:(NSString *)text {
  UILabel *label = [[UILabel alloc] init];
  label.text = text;
  label.textColor = [UIColor colorWithWhite:1.0 alpha:0.88];
  label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
  return label;
}

- (UILabel *)valueLabel {
  UILabel *label = [self label:@""];
  label.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
  label.textAlignment = NSTextAlignmentRight;
  [label.widthAnchor constraintEqualToConstant:42.0].active = YES;
  return label;
}

- (UIButton *)actionButton:(NSString *)title selector:(SEL)selector {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
  [button setTitle:title forState:UIControlStateNormal];
  button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
  button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
  button.layer.cornerRadius = 10.0;
  button.layer.cornerCurve = kCACornerCurveContinuous;
  [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
  return button;
}

- (UIStackView *)sliderRowWithLabel:(UILabel *)label
                              slider:(UISlider *)slider
                               value:(UILabel *)value {
  UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ label, slider, value ]];
  row.axis = UILayoutConstraintAxisHorizontal;
  row.alignment = UIStackViewAlignmentCenter;
  row.spacing = 10.0;
  [label.widthAnchor constraintEqualToConstant:88.0].active = YES;
  return row;
}

- (UIStackView *)rowWithLabel:(UILabel *)label
                      control:(UIView *)control
                 controlWidth:(CGFloat)controlWidth {
  UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ label, control ]];
  row.axis = UILayoutConstraintAxisHorizontal;
  row.alignment = UIStackViewAlignmentCenter;
  row.distribution = UIStackViewDistributionEqualSpacing;
  [control.widthAnchor constraintEqualToConstant:controlWidth].active = YES;
  return row;
}

- (void)didMoveToSuperview {
  [super didMoveToSuperview];
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  _opacitySlider.value = [defaults objectForKey:kOpacityKey] ? [defaults floatForKey:kOpacityKey] : 0.72;
  _scaleSlider.value = [defaults objectForKey:kScaleKey] ? [defaults floatForKey:kScaleKey] : 1.0;
  BOOL autoHide = ![defaults objectForKey:kAutoHideKey] || [defaults boolForKey:kAutoHideKey];
  _visibilityControl.selectedSegmentIndex = autoHide ? 1 : 0;
  [self updateValueLabels];
}

- (void)updateValueLabels {
  _opacityValue.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(_opacitySlider.value * 100.0f)];
  _scaleValue.text = [NSString stringWithFormat:@"%d%%", (int)lroundf(_scaleSlider.value * 100.0f)];
}

- (void)opacityChanged {
  [self updateValueLabels];
  [self.overlay setControlOpacity:_opacitySlider.value];
}

- (void)scaleChanged {
  [self updateValueLabels];
  [self.overlay setControlScale:_scaleSlider.value];
}

- (void)persistSliders {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  [defaults setFloat:_opacitySlider.value forKey:kOpacityKey];
  [defaults setFloat:_scaleSlider.value forKey:kScaleKey];
}

- (void)visibilityChanged {
  BOOL autoHide = _visibilityControl.selectedSegmentIndex == 1;
  [self.overlay setAutoHideEnabled:autoHide];
}

- (void)requestAction:(uint32_t)action {
  [self close];
  [self.overlay requestAction:action];
}

- (void)saveState {
  [self requestAction:kIosImplActionSaveState];
}

- (void)loadState {
  [self beginConfirmation:@"Load quick save?"
              actionTitle:@"Load"
                   action:kIosImplActionLoadState];
}

- (void)resetGame {
  [self beginConfirmation:@"Reset the game?"
              actionTitle:@"Reset"
                   action:kIosImplActionReset];
}

- (void)quitGame {
  [self beginConfirmation:@"Quit the game?"
              actionTitle:@"Quit"
                   action:kIosImplActionQuit];
}

- (void)beginConfirmation:(NSString *)prompt
              actionTitle:(NSString *)actionTitle
                   action:(uint32_t)action {
  _confirmationAction = action;
  _confirmationLabel.text = prompt;
  [_confirmationButton setTitle:actionTitle forState:UIControlStateNormal];
  _confirmationButton.tintColor = action == kIosImplActionLoadState
                                      ? UIColor.systemBlueColor
                                      : [UIColor colorWithRed:1.0 green:0.42 blue:0.38 alpha:1.0];
  _actions.hidden = YES;
  _confirmationRow.hidden = NO;
  UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,
                                  _confirmationLabel);
}

- (void)cancelConfirmation {
  _confirmationAction = 0;
  _confirmationRow.hidden = YES;
  _actions.hidden = NO;
}

- (void)confirmPendingAction {
  uint32_t action = _confirmationAction;
  [self cancelConfirmation];
  if (action)
    [self requestAction:action];
}

- (void)close {
  [self cancelConfirmation];
  [self removeFromSuperview];
  [self.overlay settingsDidClose];
}

@end

@implementation SMWTouchOverlay {
  SMWDpadView *_dpad;
  NSArray<SMWTouchButton *> *_gameButtons;
  SMWTouchButton *_buttonA;
  SMWTouchButton *_buttonB;
  SMWTouchButton *_buttonX;
  SMWTouchButton *_buttonY;
  SMWTouchButton *_buttonL;
  SMWTouchButton *_buttonR;
  SMWTouchButton *_buttonStart;
  SMWTouchButton *_buttonSelect;
  SMWControlSettings *_settings;
  CGFloat _controlScale;
  CGFloat _controlOpacity;
  BOOL _controllerConnected;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.clearColor;
    self.multipleTouchEnabled = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    UIColor *red = [UIColor colorWithRed:0.91 green:0.23 blue:0.22 alpha:1.0];
    UIColor *yellow = [UIColor colorWithRed:0.97 green:0.72 blue:0.18 alpha:1.0];
    UIColor *blue = [UIColor colorWithRed:0.20 green:0.52 blue:0.91 alpha:1.0];
    UIColor *green = [UIColor colorWithRed:0.25 green:0.72 blue:0.35 alpha:1.0];
    UIColor *neutral = [UIColor colorWithWhite:0.82 alpha:1.0];

    _dpad = [[SMWDpadView alloc] initWithFrame:CGRectZero];
    _buttonA = [self button:@"A" mask:kButtonA accent:red label:@"Spin jump"];
    _buttonB = [self button:@"B" mask:kButtonB accent:yellow label:@"Jump"];
    _buttonX = [self button:@"X" mask:kButtonX accent:blue label:@"Secondary action"];
    _buttonY = [self button:@"Y" mask:kButtonY accent:green label:@"Run and action"];
    _buttonL = [self button:@"L" mask:kButtonL accent:neutral label:@"Scroll camera left"];
    _buttonR = [self button:@"R" mask:kButtonR accent:neutral label:@"Scroll camera right"];
    _buttonStart = [self button:@"START" mask:kButtonStart accent:red label:@"Start and pause"];
    _buttonSelect = [self button:@"SELECT" mask:kButtonSelect accent:neutral label:@"Select"];
    _menuButton = [self button:@"•••" mask:0 accent:blue label:@"Game menu"];
    [_menuButton removeTarget:_menuButton action:@selector(pressed) forControlEvents:UIControlEventTouchDown];
    [_menuButton removeTarget:_menuButton action:@selector(released)
                 forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                  UIControlEventTouchCancel];
    [_menuButton addTarget:self action:@selector(openSettings)
          forControlEvents:UIControlEventTouchUpInside];

    _gameButtons = @[ _buttonA, _buttonB, _buttonX, _buttonY, _buttonL, _buttonR,
                      _buttonStart, _buttonSelect ];
    [self addSubview:_dpad];
    for (SMWTouchButton *button in _gameButtons)
      [self addSubview:button];
    [self addSubview:_menuButton];
    [self applyPreferences];
  }
  return self;
}

- (SMWTouchButton *)button:(NSString *)title
                      mask:(uint32_t)mask
                    accent:(UIColor *)accent
                     label:(NSString *)label {
  return [[SMWTouchButton alloc] initWithLabel:title mask:mask accent:accent accessibilityLabel:label];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *hit = [super hitTest:point withEvent:event];
  return hit == self ? nil : hit;
}

- (void)safeAreaInsetsDidChange {
  [super safeAreaInsetsDidChange];
  [self setNeedsLayout];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
  BOOL pad = self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad;
  CGFloat scale = _controlScale * (pad ? MIN(1.18, CGRectGetHeight(safe) / 650.0) : 1.0);
  CGFloat face = (pad ? 72.0 : 60.0) * scale;
  CGFloat bottom = CGRectGetMaxY(safe) - (pad ? 32.0 : 16.0);

  CGFloat dpadSize = (pad ? 164.0 : 132.0) * scale;
  _dpad.frame = CGRectMake(CGRectGetMinX(safe) + (pad ? 28.0 : 14.0), bottom - dpadSize,
                           dpadSize, dpadSize);

  CGFloat right = pad ? CGRectGetMaxX(safe) - 28.0 : CGRectGetMaxX(self.bounds) - 18.0;
  CGFloat step = face * (pad ? 0.82 : 0.80);
  CGPoint faceCenter =
      CGPointMake(right - face * 0.5 - step, bottom - face * 0.5 - step);
  CGPoint yCenter = CGPointMake(faceCenter.x - step, faceCenter.y);
  CGPoint aCenter = CGPointMake(faceCenter.x + step, faceCenter.y);
  CGPoint xCenter = CGPointMake(faceCenter.x, faceCenter.y - step);
  CGPoint bCenter = CGPointMake(faceCenter.x, faceCenter.y + step);
  _buttonY.frame = CGRectMake(yCenter.x - face * 0.5, yCenter.y - face * 0.5, face, face);
  _buttonB.frame = CGRectMake(bCenter.x - face * 0.5, bCenter.y - face * 0.5, face, face);
  _buttonX.frame = CGRectMake(xCenter.x - face * 0.5, xCenter.y - face * 0.5, face, face);
  _buttonA.frame = CGRectMake(aCenter.x - face * 0.5, aCenter.y - face * 0.5, face, face);

  CGFloat shoulderWidth = (pad ? 82.0 : 68.0) * scale;
  CGFloat shoulderHeight = (pad ? 44.0 : 38.0) * scale;
  _buttonL.frame = CGRectMake(CGRectGetMinX(safe) + 18.0, CGRectGetMinY(safe) + 14.0,
                              shoulderWidth, shoulderHeight);
  _buttonR.frame = CGRectMake(CGRectGetMaxX(safe) - shoulderWidth - 18.0,
                              CGRectGetMinY(safe) + 14.0, shoulderWidth, shoulderHeight);

  CGFloat systemWidth = (pad ? 76.0 : 64.0) * scale;
  CGFloat systemHeight = (pad ? 36.0 : 32.0) * scale;
  CGFloat centerX = CGRectGetMidX(safe);
  CGFloat systemY = CGRectGetMinY(safe) + 14.0 + shoulderHeight + 8.0;
  _buttonSelect.frame = CGRectMake(CGRectGetMinX(_buttonL.frame), systemY,
                                   systemWidth, systemHeight);
  _buttonStart.frame = CGRectMake(CGRectGetMaxX(safe) - systemWidth - 18.0, systemY,
                                  systemWidth, systemHeight);
  _buttonSelect.titleLabel.font = [UIFont systemFontOfSize:pad ? 11.0 : 9.0
                                                       weight:UIFontWeightBold];
  _buttonStart.titleLabel.font = _buttonSelect.titleLabel.font;

  CGFloat menuSize = pad ? 44.0 : 40.0;
  _menuButton.frame = CGRectMake(centerX - menuSize * 0.5, CGRectGetMinY(safe) + 12.0,
                                 menuSize, menuSize);
  _menuButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];

  if (_settings.superview) {
    CGFloat width = MIN(390.0, CGRectGetWidth(safe) - 32.0);
    CGFloat height = MIN(250.0, CGRectGetHeight(safe) - 24.0);
    _settings.frame = CGRectMake(centerX - width * 0.5, CGRectGetMidY(safe) - height * 0.5,
                                 width, height);
  }
}

- (void)openSettings {
  [self releaseAll];
  if (!_settings) {
    _settings = [[SMWControlSettings alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    _settings.overlay = self;
  }
  [self addSubview:_settings];
  _menuButton.hidden = YES;
  [self updateGameControlVisibility];
  [self setNeedsLayout];
}

- (void)applyPreferences {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  _controlOpacity = [defaults objectForKey:kOpacityKey] ? [defaults floatForKey:kOpacityKey] : 0.72;
  _controlScale = [defaults objectForKey:kScaleKey] ? [defaults floatForKey:kScaleKey] : 1.0;
  [self updateGameControlVisibility];
  [self setNeedsLayout];
}

- (void)setControlOpacity:(CGFloat)opacity {
  _controlOpacity = opacity;
  [self updateGameControlVisibility];
}

- (void)setControlScale:(CGFloat)scale {
  _controlScale = scale;
  [self setNeedsLayout];
}

- (void)setAutoHideEnabled:(BOOL)enabled {
  [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kAutoHideKey];
  [self updateGameControlVisibility];
}

- (void)settingsDidClose {
  _menuButton.hidden = NO;
  [self updateGameControlVisibility];
}

- (void)requestAction:(uint32_t)action {
  gPendingActions.fetch_or(action, std::memory_order_relaxed);
}

- (void)updateGameControlVisibility {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  BOOL autoHide = ![defaults objectForKey:kAutoHideKey] || [defaults boolForKey:kAutoHideKey];
  BOOL hidden = _settings.superview != nil || (autoHide && _controllerConnected);
  _dpad.hidden = hidden;
  _dpad.alpha = _controlOpacity;
  for (SMWTouchButton *button in _gameButtons) {
    button.hidden = hidden;
    button.alpha = _controlOpacity;
  }
}

- (void)setControllerConnected:(BOOL)connected {
  _controllerConnected = connected;
  if (connected)
    [self releaseAll];
  [self updateGameControlVisibility];
}

- (void)releaseAll {
  gTouchInput.store(0, std::memory_order_relaxed);
  [_dpad forceRelease];
  for (SMWTouchButton *button in _gameButtons)
    [button forceRelease];
}

@end

namespace {

__weak SMWTouchOverlay *gOverlay;

bool CopyResourceIfNeeded(NSFileManager *manager, NSString *name, NSString *destination) {
  if ([manager fileExistsAtPath:destination])
    return true;
  NSString *source = [NSBundle.mainBundle pathForResource:name ofType:nil];
  if (!source)
    return false;
  NSError *error = nil;
  if (![manager copyItemAtPath:source toPath:destination error:&error]) {
    NSLog(@"SMW iOS: failed to copy %@: %@", name, error.localizedDescription);
    return false;
  }
  return true;
}

}  // namespace

extern "C" bool IosImpl_PrepareRuntime(void) {
  @autoreleasepool {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *documents = [manager URLsForDirectory:NSDocumentDirectory
                                       inDomains:NSUserDomainMask].firstObject;
    if (!documents)
      return false;
    NSError *error = nil;
    if (![manager createDirectoryAtURL:documents
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error]) {
      NSLog(@"SMW iOS: failed to create Documents: %@", error.localizedDescription);
      return false;
    }
    NSString *directory = documents.path;
    if (!CopyResourceIfNeeded(manager, @"smw.ini",
                              [directory stringByAppendingPathComponent:@"smw.ini"]) ||
        !CopyResourceIfNeeded(manager, @"smw_assets.dat",
                              [directory stringByAppendingPathComponent:@"smw_assets.dat"])) {
      NSLog(@"SMW iOS: the app bundle is missing smw.ini or smw_assets.dat");
      return false;
    }
    return chdir(directory.fileSystemRepresentation) == 0;
  }
}

extern "C" void IosImpl_ConfigureAudioSession(void) {
  AVAudioSession *session = AVAudioSession.sharedInstance;
  NSError *error = nil;
  [session setCategory:AVAudioSessionCategoryAmbient
                  mode:AVAudioSessionModeDefault
               options:AVAudioSessionCategoryOptionMixWithOthers
                 error:&error];
  if (error)
    NSLog(@"SMW iOS: audio category error: %@", error.localizedDescription);
  error = nil;
  [session setPreferredSampleRate:48000.0 error:&error];
  if (error)
    NSLog(@"SMW iOS: sample-rate preference error: %@", error.localizedDescription);
  error = nil;
  [session setPreferredIOBufferDuration:0.010 error:&error];
  if (error)
    NSLog(@"SMW iOS: buffer preference error: %@", error.localizedDescription);
  IosImpl_SetAudioSessionActive(true);
}

extern "C" void IosImpl_SetAudioSessionActive(bool active) {
  NSError *error = nil;
  AVAudioSessionSetActiveOptions options =
      active ? 0 : AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation;
  [AVAudioSession.sharedInstance setActive:active withOptions:options error:&error];
  if (error)
    NSLog(@"SMW iOS: audio session %@ error: %@", active ? @"activation" : @"deactivation",
          error.localizedDescription);
}

extern "C" void IosImpl_InstallTouchControls(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *window = ActiveWindow();
    if (!window)
      return;
    SMWTouchOverlay *overlay = gOverlay;
    if (!overlay) {
      overlay = [[SMWTouchOverlay alloc] initWithFrame:window.bounds];
      gOverlay = overlay;
    }
    if (overlay.superview != window)
      [window addSubview:overlay];
    overlay.frame = window.bounds;
    [overlay setControllerConnected:gControllerConnected.load(std::memory_order_relaxed)];
    [window bringSubviewToFront:overlay];
#if TARGET_OS_SIMULATOR
    if (getenv("SMW_IOS_OPEN_MENU"))
      [overlay openSettings];
#endif
  });
}

extern "C" void IosImpl_SetControllerConnected(bool connected) {
#if TARGET_OS_SIMULATOR
  // CoreSimulator exposes a synthetic "Gamepad" for keyboard forwarding.
  // Keep touch controls visible there so phone/tablet layouts can be tested.
  connected = false;
#endif
  gControllerConnected.store(connected, std::memory_order_relaxed);
  dispatch_async(dispatch_get_main_queue(), ^{
    [gOverlay setControllerConnected:connected];
  });
}

extern "C" void IosImpl_ReleaseAllInputs(void) {
  gTouchInput.store(0, std::memory_order_relaxed);
  dispatch_async(dispatch_get_main_queue(), ^{
    [gOverlay releaseAll];
  });
}

extern "C" uint32_t IosImpl_GetTouchInput(void) {
  return gTouchInput.load(std::memory_order_relaxed);
}

extern "C" uint32_t IosImpl_TakePendingActions(void) {
  return gPendingActions.exchange(0, std::memory_order_relaxed);
}
