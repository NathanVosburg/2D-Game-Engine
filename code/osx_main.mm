// OSX Main

/**
 CONTROLS:
 	WASD - movement
	Click - shoot
	Q - exit game 
 */

#include <stdio.h>
#include <AppKit/AppKit.h>
#include <IOKit/hid/IOHIDLib.h>
#include<iostream>    
#include<array>
#include <mach/mach_init.h>
#include <mach/mach_time.h>
#include <mach-o/dyld.h>

#define internal static
#define local_persist static
#define global_variable static

const int numTurrets = 4;
const double gameSpeed = 7.0;
const double PI = 3.14159265358979323846;
const double TWO_PI = 6.28318530718;
const double HALF_PI = 1.57079632679;

typedef int32_t bool32;

typedef float real32;
typedef double real64;

global_variable int bitmapWidth;
global_variable int bitmapHeight;
global_variable int bytesPerPixel = 4;
global_variable int pitch;
global_variable uint16_t frames = 0;

global_variable int GlobalRenderingWidth = 1024;
global_variable int GlobalRenderingHeight = 768;
global_variable uint8_t *buffer;
global_variable bool Running = true;

struct mac_game_controller
{
    bool wKeyState;
    bool aKeyState;
    bool sKeyState;
    bool dKeyState;
    float mouseX;
    float mouseY;
};

struct Position {
	double posX;
	double posY;

	Position(double x, double y) {
		posX = x;
		posY = y;
	}

	Position() {
		posX = 0;
		posY = 0;
	}

	double length() {return sqrt(posX * posX + posY * posY);}
	void add(Position a) { posX += a.posX; posY += a.posY;}
	Position mul(double c) { posX *= c; posY *= c; return *this;}
	Position unitVector() { return Position::divide( {posX, posY} , length());}
	
	static Position add(Position a, Position b) {return Position(a.posX+b.posX, a.posY+b.posY);}
	static Position sub(Position a, Position b) {return Position(a.posX-b.posX, a.posY-b.posY);}
	static Position divide(Position a, Position b) {return Position(a.posX/b.posX, a.posY/b.posY);}
    static Position divide(Position a, double n) {return { a.posX/n, a.posY/n } ;}
	static double slope(Position a, Position b) {
		if (a.posX == b.posX) {return std::numeric_limits<double>::infinity();}
		if (a.posY == b.posY) {return 0;}
		double slope = (a.posY-b.posY)/(a.posX-b.posX);
		return slope;}

    static Position unitVector(Position start, Position end) {
        return Position{ Position::divide(Position::sub(end, start), Position::sub(end, start).length())};}

};

union Color {
	struct {
		uint8_t red;
		uint8_t green;
		uint8_t blue;
		uint8_t alpha;
	};
	uint8_t data[4];

	Color(uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
		red = r;
		green = g;
		blue = b;
		alpha = a;
	}

	Color(uint8_t r, uint8_t g, uint8_t b) {
		red = r;
		green = g;
		blue = b;
		alpha = 255;
	}

	Color() {
		red = 0;
		green = 0;
		blue = 0;
		alpha = 0;
	}
};


struct Turret {
	Position position;
	int radius;
	Color color;
	int team;
	int cooldown;
	int currentHealth;
	int maxHealth;
	int framesSinceFired;
};
struct Bullet {
	Position position;
	int radius;
	Position velocity;
	int team;
	bool alive;

	Bullet(Position p, int r, Position v, int t) {
		position = p;
		radius = r;
		velocity = v;
		team = t;
		alive = true;
	}

	Bullet() {
		position = Position();
		velocity = Position();
		int team = -1;
		alive = false;
	}
};

const Color Red(255, 0, 0);
const Color Green(0, 255, 0);
const Color Blue(0, 0, 255);
const Color TeamColors[3] = {Green, Red, Red};


static mac_game_controller KeyboardController = {};
static mac_game_controller *GameController = &KeyboardController; 

const uint16 wKeyCode = 0x0D;
const uint16 aKeyCode = 0x00;
const uint16 sKeyCode = 0x01;
const uint16 dKeyCode = 0x02;
const uint16 qKeyCode = 0x0C;

const int TeamPlayer = 0;
const int TeamEnemy = 1;
const int NoTeam = 2;

Position mousePos;
Turret player;
Bullet bullets[1024];
Turret turrets[numTurrets];



int max(int a, int b) {
	return a > b ? a : b; }
int min(int a , int b) {
	return a < b ? a : b; }
bool between(int a, int b, int c) {
	return a < b && b < c;}

bool circleTouch(Position p1, int r1, Position p2, int r2) {
	return (p1.posX - p2.posX) * (p1.posX - p2.posX) + (p1.posY - p2.posY) * (p1.posY - p2.posY) <= (r1 + r2) * (r1 + r2);}
bool circleTouch(Bullet b, Turret t) {
	return circleTouch(b.position, b.radius, t.position, t.radius);}

//refreshes buffer
void macOSRefreshBuffer(NSWindow *Window) {
	if (buffer) {
		free(buffer);
	}

	bitmapWidth = Window.contentView.bounds.size.width;
    bitmapHeight = Window.contentView.bounds.size.height;
    pitch = bitmapWidth * bytesPerPixel;
    buffer = (uint8_t *)malloc(pitch * bitmapHeight);
}

// wipes buffer
internal void clearScreen() {
	memset(buffer, 0, pitch * bitmapHeight);	 
}

internal double boundedMin(double nums[], int n, double lowBound) {
	double min = std::numeric_limits<double>::max();
	for(int i = 0; i < n; i++) {
		min = nums[i] < min && nums[i] >= lowBound ? nums[i] : min;
	}
	NSLog(@"min: %f", min);
	return min;
}

internal double bounded2Min(double nums[], int n, double lowBound) {
	double min = std::numeric_limits<double>::max();
	double min2 = std::numeric_limits<double>::max();
	for(int i = 0; i < n; i++) {
		if (nums[i] < min && nums[i] >= lowBound) {
			min2 = min;
			min = nums[i];
		} else if (nums[i] < min2 && nums[i] >= lowBound) {
			min2 = nums[i];}
	}
	NSLog(@"min2: %f", min2);
	return min2;
}

internal void flatBottomTriangle(Position p1, Position p2, Position p3, Color c) {
	if (p1.posY < p2.posY) {Position temp = p1; p1 = p2; p2 = temp;}
	if (p1.posY < p3.posY) {Position temp = p1; p1 = p3; p3 = temp;}
	if (p2.posX > p3.posX) {Position temp = p2; p2 = p3; p3 = temp;}
	double yMax = p1.posY;
	double closeSlope = Position::slope(p1, p2);
	double farSlope = Position::slope(p1, p3);

	uint8_t *row = (uint8_t *)buffer;
	row += pitch * (int)yMax;
	for(int curY = yMax; curY >= p2.posY; curY--) {
		int startX = (int) ((curY - p1.posY) / closeSlope + p1.posX);
		int endX = (int) ((curY - p1.posY) / farSlope + p1.posX);
		uint8_t *pixelChannel = (uint8_t *)row;
		pixelChannel += max(startX, 0)*4;
		for(int curX = startX; curX <= endX; curX++) {
			memcpy(pixelChannel, &c, sizeof(Color));
			pixelChannel+=4; }
		row -= pitch;
	}
}

internal void flatTopTriangle(Position p1, Position p2, Position p3, Color c) {
	if (p1.posY > p2.posY) {Position temp = p1; p1 = p2; p2 = temp;}
	if (p1.posY > p3.posY) {Position temp = p1; p1 = p3; p3 = temp;}
	if (p2.posX > p3.posX) {Position temp = p2; p2 = p3; p3 = temp;}
	double yMin = p1.posY;
	double closeSlope = Position::slope(p1, p2);
	double farSlope = Position::slope(p1, p3);

	uint8_t *row = (uint8_t *)buffer;
	row += pitch * (int)yMin;
	for(int curY = yMin; curY <= p2.posY; curY++) {
		int startX = (int) ((curY - p1.posY) / closeSlope + p1.posX);
		int endX = (int) ((curY - p1.posY) / farSlope + p1.posX);
		uint8_t *pixelChannel = (uint8_t *)row;
		pixelChannel += max(startX, 0)*4;
		for(int curX = startX; curX <= endX; curX++) {
			memcpy(pixelChannel, &c, sizeof(Color));
			pixelChannel+=4; }
		row += pitch;
	}
}

internal void drawTriangle(Position p1, Position p2, Position p3, Color c) {
	if (p2.posY < p3.posY) {Position temp = p2; p2 = p3; p3 = temp;}
	if (p1.posY > p2.posY) {Position temp = p1; p1 = p2; p2 = temp;}
	if (p1.posY < p3.posY) {Position temp = p1; p1 = p3; p3 = temp;}
	double slope = Position::slope(p2, p3);

	Position point = {(p1.posY - p2.posY) / slope + p2.posX, p1.posY};
	flatTopTriangle(p1, p3, point, Red);
	flatBottomTriangle(p1, p2, point, Red);
}

// regular polygon
struct RegNgon {
	Position center;
	double radius;
	int sides;
	Color color;
	double rpm;
	double maxHP;
	double curHP;

	void draw() {
		Position last = {center.posX + radius, center.posY};
		double step = TWO_PI/sides;
		for(double theta = step; theta < TWO_PI + step; theta += step) {
			Position next = {center.posX + radius * cos(theta), center.posY + radius * sin(theta)};
			drawTriangle(center, last, next, color);
			last = next;
		}
	}

	void drawRotating() {
		Position last = {center.posX + (double)radius * cos(frames/(600.0/rpm)), center.posY + (double)radius * sin(frames/(600.0/rpm))};
		double step = TWO_PI/sides;
		double offset = step + atan2((last.posY-center.posY), (last.posX-center.posX));
		for(double theta = offset; theta < TWO_PI + offset; theta += step) {
			Position next = {center.posX + radius * cos(theta), center.posY + radius * sin(theta)};
			drawTriangle(center, last, next, color);
			last = next;
		}
	}
};


struct ConcaveNgon{
	int sides;
	Position *points;
	Color color;
	double rpm;
	Position center;
	double maxHP = 1;
	double curHP = 1;


	ConcaveNgon(int s, Position p[], Color c, double r, double max, double cur) {
		sides = s;
		points = p;
		color = c;
		rpm = r;
		maxHP = max;
		curHP = cur;
		double xPos = 0;
		double yPos = 0;
		for(int n = 0; n < sides; n++) {
			xPos += p[n].posX;
			yPos += p[n].posY;
		}
		center = {xPos/sides, yPos/sides};
	}

	ConcaveNgon(int s, Position p[], Color c, double r) {
		sides = s;
		points = p;
		color = c;
		rpm = r;
		double xPos = 0;
		double yPos = 0;
		for(int n = 0; n < sides; n++) {
			xPos += p[n].posX;
			yPos += p[n].posY;
		}
		center = {xPos/sides, yPos/sides};
	}

	void draw() {
		if(maxHP == curHP) {
			for(int n = 0; n < sides-1; n++) {
				drawTriangle(center, points[n], points[n+1], color);
			} drawTriangle(center, points[0], points[sides-1], color);
		} else { 
			for(int n = 0; n < sides-1; n++) {
				drawTriangle(points[n], points[n+1], Position{(points[n].posX-center.posX)*curHP/maxHP+center.posX, (points[n].posY-center.posY)*curHP/maxHP+center.posY}, color);
				drawTriangle(points[n+1], Position{(points[n].posX-center.posX)*curHP/maxHP+center.posX, (points[n].posY-center.posY)*curHP/maxHP+center.posY}, Position{(points[n+1].posX-center.posX)*curHP/maxHP+center.posX, (points[n+1].posY-center.posY)*curHP/maxHP+center.posY}, color);
				/*Position a[] = {points[n], points[n+1], Position{(points[n].posX-center.posX)*curHP/maxHP+center.posX, (points[n].posY-center.posY)*curHP/maxHP+center.posY}, Position{(points[n+1].posX-center.posX)*curHP/maxHP+center.posX, (points[n+1].posY-center.posY)*curHP/maxHP+center.posY}};
				//TODO TODO TODO mqthy math math math
				ConcaveNgon{4, a, color, rpm}.draw();*/
			}
				drawTriangle(points[0], points[sides-1], Position{(points[0].posX-center.posX)*curHP/maxHP+center.posX, (points[0].posY-center.posY)*curHP/maxHP+center.posY}, color);
				drawTriangle(points[sides-1], Position{(points[0].posX-center.posX)*curHP/maxHP+center.posX, (points[0].posY-center.posY)*curHP/maxHP+center.posY}, Position{(points[sides-1].posX-center.posX)*curHP/maxHP+center.posX, (points[sides-1].posY-center.posY)*curHP/maxHP+center.posY}, color);
		}
	}
/*
	void drawRotating() {
		Position last = {center.posX + (double)radius * cos(frames/(600.0/rpm)), center.posY + (double)radius * sin(frames/(600.0/rpm))};
		double step = TWO_PI/sides;
		double offset = step + atan2((last.posY-center.posY), (last.posX-center.posX));
		for(double theta = offset; theta < TWO_PI + offset; theta += step) {
			Position next = {center.posX + radius * cos(theta), center.posY + radius * sin(theta)};
			drawTriangle(center, last, next, color);
			last = next;
		}
	}*/
};

internal void drawRotatingNgon(Position center, int radius, int sides, Color c, double rpm) {
	Position last = {center.posX + (double)radius * cos(frames/(600.0/rpm)), center.posY + (double)radius * sin(frames/(600.0/rpm))};
	double step = TWO_PI/sides;
    double offset = step + atan2((last.posY-center.posY), (last.posX-center.posX));
	for(double theta = offset; theta < TWO_PI + offset; theta += step) {
		Position next = {center.posX + radius * cos(theta), center.posY + radius * sin(theta)};
		drawTriangle(center, last, next, c);
		last = next;
	}
}

internal void drawNgon(Position center, int radius, int n, Color c) {
	Position last = {center.posX + radius, center.posY};
	double step = TWO_PI/n;
	for(double theta = step; theta < TWO_PI + step; theta += step) {
		Position next = {center.posX + radius * cos(theta), center.posY + radius * sin(theta)};
		drawTriangle(center, last, next, c);
		last = next;
	}
}

// draws a circle ... wow
internal void drawCircle(Position p, int r, Color c) {
	int width = bitmapWidth;
	int height = bitmapHeight;
	uint8_t *row = (uint8_t *)buffer;
	int posY = (int)p.posY;
	int posX = (int)p.posX;
	int rr = r*r;

	row += max(posY-r, 0) * pitch;
	for(int y = max(posY-r, 0); y < min(posY+r, height); ++y) {
		uint8_t *pixelChannel = (uint8_t *)row;
		pixelChannel+= max(posX-r, 0)*4;
		for(int x = max(posX-r, 0); x < min(posX+r, width); ++x) {
			if ((posX-x) * (posX-x) + (posY-y) * (posY-y) <= rr) {
				*pixelChannel = c.red;
				++pixelChannel;
				*pixelChannel = c.green;
				++pixelChannel;
				*pixelChannel = c.blue;
				++pixelChannel;
				*pixelChannel = c.alpha;
				++pixelChannel;
			} else {
				pixelChannel+=4;
			}
		}
		row+=pitch;
	}   
}

internal void drawCircleOutline(Position p, int r, Color c) {
	int posY = (int)p.posY;
 	int posX = (int)p.posX;
	int con = 2*r*r-1;
	int x = r;
	int y = 0;
	int posXEqY = static_cast<int>(1.207 * r);
	uint8_t *rowQ1 = (uint8_t *)buffer;
	uint8_t *rowQ2 = (uint8_t *)buffer;
	uint8_t *rowQ3 = (uint8_t *)buffer;
	uint8_t *rowQ4 = (uint8_t *)buffer;
	rowQ2+=posY*pitch;
	rowQ3+=posY*pitch;
	rowQ1+=(posY+r)*pitch;
	rowQ4+=(posY+r)*pitch;
	int maxHealth = 10;
	int currentHealth = 5;
	double holeRadius = ((maxHealth-currentHealth)/(double)maxHealth * r);
	double hR2 = holeRadius * holeRadius;

	while (x >= y) {
		uint8_t *pixelChannelQ2 = (uint8_t *)rowQ2;
		uint8_t *pixelChannelQ3 = (uint8_t *)rowQ3;
		pixelChannelQ2+=posX*4;
		pixelChannelQ3+=posX*4;
		if (-2*x*x+2*x-2*y*y+con <= 0) {x--; rowQ1-=pitch; rowQ4-=pitch;}

		pixelChannelQ2-=x*4;
		pixelChannelQ3-=x*4;
		for(int quarter = -x; quarter < x; quarter++) {
			int l2 = quarter * quarter + y*y;
			//if (abs(quarter) > posXEqY) { 		// TODO maybe fix later
			/*uint8_t *pixelChannelQ1 = (uint8_t *)rowQ1;
			pixelChannelQ1+=y*4+posX*4;
			*pixelChannelQ1 = 255;
			pixelChannelQ1+=3;
			*pixelChannelQ1 = 255;
			++pixelChannelQ1;
		
			uint8_t *pixelChannelQ4 = (uint8_t *)rowQ4;
			pixelChannelQ4+=-y*4+posX*4;
			*pixelChannelQ4 = 255;
			pixelChannelQ4+=3;
			*pixelChannelQ4 = 255;
			++pixelChannelQ4;

			rowQ1-=pitch;
			rowQ4-=pitch;*/

			if (l2 >= hR2){

				*pixelChannelQ2 = 255;
				pixelChannelQ2+=3;
				*pixelChannelQ2 = 255;
				++pixelChannelQ2;
			
				*pixelChannelQ3 = 255;
				pixelChannelQ3+=3;
				*pixelChannelQ3 = 255;
				++pixelChannelQ3;
			}
			else {
				pixelChannelQ2+=4;
				pixelChannelQ3+=4;}

		}

		rowQ1+=x*2*pitch;
		rowQ2+=pitch;
		rowQ3-=pitch; 
		rowQ4+=x*2*pitch;

		y++;

		}
}
// draws a circle except with hole depending on currenthealth
internal void drawTurret(Turret t) {
	int width = bitmapWidth;
	int height = bitmapHeight;
	uint8_t *row = (uint8_t *)buffer;
	int posY = (int)t.position.posY;
	int posX = (int)t.position.posX;
	int radius = t.radius;
	int r2 = radius * radius;
	Color color = t.color;

	row += max(posY-radius, 0) * pitch;
	for(int y = max(posY-radius, 0); y < min(posY+radius, height); ++y) {

		uint8_t *pixelChannel = (uint8_t *)row;
		pixelChannel+= max(posX-radius, 0)*4;
		for(int x = max(posX-radius, 0); x < min(posX+radius, width); ++x) {
			
			//Red
			double length = Position(posX-x, posY-y).length();
			double l2 = (posX-x)*(posX-x) + (posY-y) * (posY - y);
			double holeRadius = (t.maxHealth-t.currentHealth)/(double)t.maxHealth * radius;
			if (l2 <= r2 && l2 >= holeRadius * holeRadius) {

				memcpy(pixelChannel, &color, sizeof(Color));
				pixelChannel += 4;


			} else {

				pixelChannel+=4;
			}
		}
		row+=pitch;
	}   
}

// draws a bullet
internal void drawBullet(Bullet b) {
	drawCircle(b.position, b.radius, TeamColors[b.team]); }

// incase of window resize
void macOSRedrawBuffer(NSWindow *Window) {
	@autoreleasepool {	
		NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
				initWithBitmapDataPlanes: &buffer
				pixelsWide: bitmapWidth
				pixelsHigh: bitmapHeight
				bitsPerSample: 8
				samplesPerPixel: bytesPerPixel
				hasAlpha: YES
				isPlanar: NO
				colorSpaceName: NSDeviceRGBColorSpace
				bytesPerRow: pitch
				bitsPerPixel: 32] autorelease];

		NSSize imageSize = NSMakeSize(bitmapWidth, bitmapHeight);
		NSImage *image = [[[NSImage alloc] initWithSize: imageSize] autorelease];
		[image addRepresentation: rep];
		Window.contentView.layer.contents = image;
	} 
}

@interface TwinMainWindowDelegate: NSObject<NSWindowDelegate>
@end

@implementation TwinMainWindowDelegate

- (void)WindowWillClose:(id)sender {
    Running = false;
}
- (void)WindowDidResize:(NSNotification *)notification {
    NSWindow *Window = (NSWindow*)notification.object;
    macOSRefreshBuffer(Window);
    macOSRedrawBuffer(Window);
}
@end

//initial screen
void startup() {
	memset(bullets, 0, sizeof(bullets));
	if (player.currentHealth > 0){
		player.currentHealth ++;
		player.maxHealth++;
	}
	else player = {Position(512, 380), 10, Blue, TeamPlayer, 32, 1, 1};
	for (Turret &t: turrets) {
		t = { Position(rand() % (GlobalRenderingWidth-50) +25, rand() % (GlobalRenderingHeight-50)+25), 20, Red, 1, 30, 10, 10 };
	}
}

//fire bullet
void fireBullet(Turret source, Position target) {
	for (Bullet &b: bullets) {
		if (!b.alive) {
			b = { source.position, 5, Position::unitVector(source.position, target).mul(gameSpeed), source.team};
			return;
		}
	}	
}

//bullet updates
void simulateBullets() { 
	for (Bullet &b: bullets) {
		if (b.alive) {
			if (between(0-b.radius, b.position.posX, bitmapWidth+b.radius) && between(0-b.radius, b.position.posY, bitmapHeight+b.radius)) {
				if (b.team != player.team && circleTouch(b, player)) {
					player.currentHealth--;
					b.alive = false;}
				for (Turret &t: turrets) {
					if (t.currentHealth > 0 && b.team != t.team && circleTouch(b, t)) {
						b.alive = false;
						t.currentHealth--;
					}
				}
				drawBullet(b);
				b.position = Position::add(b.position, b.velocity);
			}
			else {
				b.alive = false; }
		}
	}
}

// turret updates
void simulateTurrets() {
	for (Turret &t: turrets) {
		if (t.currentHealth > 0){
			drawTurret(t);
			if (t.framesSinceFired++ > t.cooldown) {
				fireBullet(t, player.position);
				t.framesSinceFired = 0;}
		}
	}
}

// checks to see if need reset
void checkGameState() {
	if (player.currentHealth <= 0) startup();
	for (Turret &t: turrets) {
		if (t.currentHealth > 0) { return; }}
	startup();
}

//checks time between even a and b
internal real32
macGetSecondsElapsed(mach_timebase_info_data_t *timeBase,
                     uint64 start, uint64 end)
{
    uint64_t elapsed = end - start;
	// convert from nanoseconds
    real32 result = (real32)(elapsed * (timeBase->numer / timeBase->denom)) / 1000.0f / 1000.0f / 1000.0f;
    return (result);
}

void game() {
	simulateBullets();
	simulateTurrets();
	drawTurret(player);
	checkGameState();
}

int main(int args, const char * argv[]) {

    TwinMainWindowDelegate *MainWindowDelegate = [[TwinMainWindowDelegate alloc] init];
       
	// Allocate a sindow and show it
	NSRect screenRect = [[NSScreen mainScreen] frame];

	NSRect WindowRect = NSMakeRect((screenRect.size.width - GlobalRenderingWidth) *0.5,
			(screenRect.size.height - GlobalRenderingHeight) * 0.5, 
			GlobalRenderingWidth,
			GlobalRenderingHeight);

	NSWindow *Window = [[NSWindow alloc] initWithContentRect: WindowRect
			styleMask: NSWindowStyleMaskTitled |
					NSWindowStyleMaskClosable |
					NSWindowStyleMaskMiniaturizable |
					NSWindowStyleMaskResizable
			backing: NSBackingStoreBuffered
			defer: NO];

	[Window setBackgroundColor: NSColor.blackColor];
	[Window setTitle: @"Twinstick"];
	[Window makeKeyAndOrderFront: nil];
    [Window setDelegate: MainWindowDelegate];
    Window.contentView.wantsLayer = YES; 

	macOSRefreshBuffer(Window);

	//  frame logic initiation to allow for frame rate alignment
	int32_t monitorRefreshHz = 120;
	real32 targetFramesPerSecond = monitorRefreshHz / 2.0f;
	real32 targetSecondsPerFrame = 1.0f / targetFramesPerSecond;

    mach_timebase_info_data_t timeBase;
    mach_timebase_info(&timeBase);

    uint64_t lastCounter = mach_absolute_time();  

	//main run loop
	while (Running) {

		NSEvent* event;	
    
	    do {
			//checks event list for key and mouse events
			event = [NSApp nextEventMatchingMask: NSEventMaskAny
					untilDate: nil
					inMode: NSDefaultRunLoopMode
					dequeue: YES];
			switch ([event type]) {
				case NSEventTypeKeyDown:
					if (event.keyCode == wKeyCode) { KeyboardController.wKeyState = true; }
					if (event.keyCode == aKeyCode) { KeyboardController.aKeyState = true; }
					if (event.keyCode == sKeyCode) { KeyboardController.sKeyState = true; }
					if (event.keyCode == dKeyCode) { KeyboardController.dKeyState = true; }
					if (event.keyCode == qKeyCode) { Running = false;}
					[NSApp sendEvent: event];
					break;
				case NSEventTypeKeyUp:
					if (event.keyCode == wKeyCode) { KeyboardController.wKeyState = false; }
					if (event.keyCode == aKeyCode) { KeyboardController.aKeyState = false; }
					if (event.keyCode == sKeyCode) { KeyboardController.sKeyState = false; }
					if (event.keyCode == dKeyCode) { KeyboardController.dKeyState = false; }
					[NSApp sendEvent: event];
					break;
				case NSEventTypeLeftMouseDown:
                    mousePos = { event.locationInWindow.x, -(event.locationInWindow.y-760) };
					fireBullet(player, mousePos);
					break;
				default:
					[NSApp sendEvent: event];
			}	
		} while (event != nil);
		
		// upadtes player position based on buttons pressed	
		Position playerV = { 0, 0 };	
        if (GameController->wKeyState == true) {playerV.posY-=10;}
        if (GameController->sKeyState == true) {playerV.posY+=10;}
        if (GameController->aKeyState == true) {playerV.posX-=10;}
        if (GameController->dKeyState == true) {playerV.posX+=10;}
		if (playerV.length() != 0)
			player.position.add( { playerV.unitVector().posX * gameSpeed,  playerV.unitVector().posY * gameSpeed});
		player.position.posX = min(player.position.posX, bitmapWidth);
		player.position.posX = max(player.position.posX, 0);
		player.position.posY = min(player.position.posY, bitmapHeight);
		player.position.posY = max(player.position.posY, 0);

		//updating game objects
		clearScreen();

		Position b[] = {Position{200, 200}, Position{200, 100}, Position{100, 100}, Position{100, 200}};
		Position a[] = {Position{200, 200}, Position{100, 100}, Position{300, 100}};
		ConcaveNgon{4, b, Red, 60, 10, 9}.draw();
		RegNgon{Position{512, 100}, 50, 6, Blue, 10}.drawRotating();	
		drawRotatingNgon(Position{512, 200}, 50, 6, Red, -10);	
		//flatBottomTriangle(Position{200, 200}, Position{100, 100}, Position{300, 100}, Red);
		//flatTopTriangle(Position{200, 200}, Position{100, 300}, Position{300, 300}, Red);
		//drawTriangle(Position{200, 200}, Position{300, 150}, Position{100, 100}, Red);
		//game();

		uint64_t counter1 = mach_absolute_time();
		//drawNgon(Position{512, 370}, 50, 40, Red);
		uint64_t counter2 = mach_absolute_time();
		NSLog(@"Fast?? Circle: %llu", (counter2-counter1));

		uint64_t counter3 = mach_absolute_time();
		//drawTurret( Turret{Position{312, 370}, 50, Red, 1, 40, 5, 10, 200});
		uint64_t counter4 = mach_absolute_time();
		NSLog(@"Normal Circle: %llu", (counter4 - counter3));
	
		

		//calculating time until next frame update
		uint64_t workCounter = mach_absolute_time();

		real32 workSeconds = macGetSecondsElapsed(&timeBase, lastCounter, workCounter);

		real32 secondsElapsedForFrame = workSeconds;


		if(secondsElapsedForFrame < targetSecondsPerFrame) {
			// calculate how long to sleep (less than time before next frame because usleep is imprecise)
			real32 underOffset = 3.0f / 1000.0f;
			real32 sleepTime = targetSecondsPerFrame - secondsElapsedForFrame - underOffset;
			useconds_t sleepMS = (useconds_t)(1000.0f * 1000.0f * sleepTime);

			//sleep cpu	
			if (sleepMS > 0) { usleep(sleepMS);}

			//lock cpu for rest of time
			while (secondsElapsedForFrame < targetSecondsPerFrame) {
				secondsElapsedForFrame = macGetSecondsElapsed(&timeBase, lastCounter, mach_absolute_time());	} 
		} else { NSLog(@"FRAME MISSED"); }

		//calculate and log frame rate
		uint64_t endOfFrameTime = mach_absolute_time();

		uint64_t timePerFrame = endOfFrameTime - lastCounter;
        
        uint64_t nanosecondsPerFrame = timePerFrame * (timeBase.numer / timeBase.denom);
        real32 secondsPerFrame = (real32)nanosecondsPerFrame * 1.0E-9;
        real32 framesPerSecond = 1 / secondsPerFrame;

        NSLog(@"Frames Per Second: %f", framesPerSecond);

		frames++;
        lastCounter = mach_absolute_time();

		macGetSecondsElapsed(&timeBase, lastCounter, workCounter);

		// 	
		macOSRedrawBuffer(Window);
	}
	printf("Twinstick Finished Building"); 
}





