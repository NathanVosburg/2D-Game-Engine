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
#include <iostream>    
#include <mach/mach_init.h>
#include <mach/mach_time.h>
#include <mach-o/dyld.h>
#include <assert.h>

#define ASSERT(b) do { if (!(b)) { \
    NSLog(@"ASSERT Line %d in %s\n", __LINE__, __FILE__); \
} } while (0)
#define STATIC_ASSERT(cond) static_assert(cond, "STATIC_ASSERT");

using namespace std;

#define internal static
#define local_persist static
#define global_variable static

const int numTurrets = 4;
const int numObjects = 1;
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

uint16 OBJECT_THING = 0;
uint16 TURRET_THING = 1;
uint16 BULLET_THING = 2;

template <typename T> struct StretchyBuffer {
    int length;
    int _capacity;
    T *data;

    T &operator [](int index) { return data[index]; }
};

template <typename T> void sbuff_push_back(StretchyBuffer<T> *buffer, T element) {
    if (buffer->_capacity == 0) {
        ASSERT(!buffer->data);
        ASSERT(buffer->length == 0);
        buffer->_capacity = 16;
        buffer->data = (T *) malloc(buffer->_capacity * sizeof(T));
    }
    if (buffer->length == buffer->_capacity) {
        buffer->_capacity *= 2;
        buffer->data = (T *) realloc(buffer->data, buffer->_capacity * sizeof(T));
    }

	NSLog(@"%d", buffer->length);
	NSLog(@"%d", buffer->_capacity);

	element = element;
	
    buffer->data[buffer->length++] = element;
}

template <typename T> void sbuff_free(StretchyBuffer<T> *buffer) {
    if (buffer->data) {
        free(buffer->data);
    }
    *buffer = {};
}

template <typename T> void sbuff_insert(StretchyBuffer<T> *buffer, int i, T element) {
    sbuff_push_back(buffer, element); // shrug-emoji
    memmove(buffer->data + i + 1, buffer->data + i, (buffer->length - i) * sizeof(T));
    buffer->data[i] = element;
}

template <typename T> void sbuff_delete(StretchyBuffer<T> *buffer, int i) {
    ASSERT(i <= buffer->length - 1);
    memmove(buffer->data + i, buffer->data + i + 1, (buffer->length - i - 1) * sizeof(T));
    --buffer->length;
}


// Player thing???
struct Position {
	double x;
	double y;

	Position(double xPos, double yPos) {
		x = xPos;
		y = yPos;
	}

	Position() {
		x = 0;
		y = 0;
	}

	double length() {return sqrt(x * x + y * y);}
	void add(Position a) { x += a.x; y += a.y;}
	Position mul(double c) { x *= c; y *= c; return *this;}
	Position unitVector() { return Position::divide( {x, y} , length());}
	
	static Position add(Position a, Position b) {return Position(a.x+b.x, a.y+b.y);}
	static Position sub(Position a, Position b) {return Position(a.x-b.x, a.y-b.y);}
	static Position divide(Position a, Position b) {return Position(a.x/b.x, a.y/b.y);}
    static Position divide(Position a, double n) {return { a.x/n, a.y/n } ;}
	static double distance(Position a, Position b) {return (a-b).length();}
	static double slope(Position a, Position b) {
		if (a.x == b.x) {return numeric_limits<double>::infinity();}
		if (a.y == b.y) {return 0;}
		double slope = (a.y-b.y)/(a.x-b.x);
		return slope;}

	static Position average(std::initializer_list<Position> list) {
		Position pos = Position();
		for(Position temp : list) {
			pos+=temp;
		}
		return divide(pos, list.size());
	}

    static Position unitVector(Position start, Position end) {
        return Position{ Position::divide(Position::sub(end, start), Position::sub(end, start).length())};}

    Position operator+(Position const& obj)
    {
        Position pos;
        pos.x = x + obj.x;
        pos.y = y + obj.y;
        return pos;
    }
    Position operator-(Position const& obj)
    {
        Position pos;
        pos.x = x - obj.x;
        pos.y = y - obj.y;
        return pos;
    }
    Position& operator+=(Position const& obj)
    {
        this->x += obj.x;
		this->y += obj.y;
		return *this;
    }
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

	bool operator==(const Color& other) {
  		return 
			this->red == other.red &&
			this->green == other.green &&
			this->blue == other.blue &&
			this->alpha == other.alpha;
	}
	bool operator!=(const Color& other) {
		return !(*this == other);
	}

	void print() {
		NSLog(@"Red: %d, Green: %d, Blue: %d, Alpha: %d", this->red, this->green, this->blue, this->alpha);
	}

};

const Color Red(255, 0, 0);
const Color Green(0, 255, 0);
const Color Blue(0, 0, 255);
const Color TeamColors[3] = {Green, Red, Red};

const uint16 qKeyCode = 0x0C;
const uint16 wKeyCode = 0x0D;
const uint16 eKeyCode = 0x0E;
const uint16 rKeyCode = 0x0F;
const uint16 tKeyCode = 0x11;
const uint16 yKeyCode = 0x10;
const uint16 uKeyCode = 0x20;
const uint16 iKeyCode = 0x22;
const uint16 oKeyCode = 0x1F;
const uint16 pKeyCode = 0x23;
const uint16 aKeyCode = 0x00;
const uint16 sKeyCode = 0x01;
const uint16 dKeyCode = 0x02;
const uint16 fKeyCode = 0x03;
const uint16 gKeyCode = 0x05;
const uint16 hKeyCode = 0x04;
const uint16 jKeyCode = 0x26;
const uint16 kKeyCode = 0x28;
const uint16 lKeyCode = 0x25;
const uint16 zKeyCode = 0x06;
const uint16 xKeyCode = 0x07;
const uint16 cKeyCode = 0x08;
const uint16 vKeyCode = 0x09;
const uint16 bKeyCode = 0x0B;
const uint16 nKeyCode = 0x2D;
const uint16 mKeyCode = 0x2E;

bool keyPressed[256];
bool keyHeld[256];

const int TeamPlayer = 0;
const int TeamEnemy = 1;
const int NoTeam = 2;

Position mousePos;
bool leftMouseButtonDown;
bool click;

int max(int a, int b) {
	return a > b ? a : b; }
int min(int a , int b) {
	return a < b ? a : b; }
bool between(int a, int b, int c) {
	return a < b && b < c;}
bool unorderedBetween(int a, int b, int c) {
	return (a < b && b < c) || (c < b && b < a);}


struct BasicImage {
	uint16 height;
	uint16 width;
	uint8 *imageData;

	void drawImage(Position a) {
		uint8 *imageFeed = imageData;
		//printf("%d", imageFeed[20*20*4-1]);
		uint8 *row = (uint8 *)buffer;
		row += pitch * (int)a.y;
		for(int i = 0; i < height; i++) {
			uint8_t *pixelChannel = (uint8_t *)row;
			pixelChannel += (int)a.x*bytesPerPixel;
			for(int j = 0; j <= width; j++) {
				memcpy(pixelChannel, imageFeed, sizeof(Color));
				pixelChannel+=4; }
			row += pitch;
			imageFeed += bytesPerPixel*width;
		}
	}
};

struct Instruction {
	uint16 write;
	uint16 jump;
	Color color;
	bool endline;
};

struct CompressedImage {
	uint16 height;
	uint16 width;
	uint32 instructionLength;
	Instruction *imageData;

	void draw(Position a) {
		uint8 *pixel = (uint8 *)buffer;
		int curY = 0;
		pixel += pitch * ((int)a.y+curY) + (int)a.x * bytesPerPixel;
		for(int i = 0; i < instructionLength; i++) {
			Instruction instruction = imageData[i];
			for(int n = 0; n < instruction.write; n++) {
				memcpy(pixel, &instruction.color, sizeof(Color));
				pixel+=bytesPerPixel;
			}
			pixel+=instruction.jump*bytesPerPixel;
			if(instruction.endline) {
				curY++;
				pixel = (uint8 *)buffer;
				pixel += pitch * ((int)a.y+curY) + (int)a.x * bytesPerPixel;

			}
		}
	}

	void print() {
		for (int i = 0; i < instructionLength; i++) {
			NSLog(@"Color: %d %d %d %d", imageData[i].color.red, imageData[i].color.green, imageData[i].color.blue, imageData[i].color.alpha);
		}
	}
};

/*
	States
	c1 c1
	c1 c2
	c1 b
	b c1
	b b
*/

// TODO: convert tp do-while loop bc this sucks
internal CompressedImage convertBasicToCompressed(BasicImage image) {
	Color savedColor = Color(image.imageData[0], image.imageData[1], image.imageData[2], image.imageData[3]);
	uint16 writeCount = 0;
	uint16 jumpCount = 0;
	bool blank = false;
	bool endline = false;
	StretchyBuffer<Instruction> instructions = {};
	int index = 0;
	int count = 0;
	do {
		Color currentColor = Color(image.imageData[index], image.imageData[index+1], image.imageData[index+2], image.imageData[index+3]);
		count++;
		if (endline) {
			savedColor = currentColor;
		}

		endline = (index/4 + 1) % image.height == 0;

		if (savedColor.alpha == 0) {
			blank = true;
		}
		if (currentColor.alpha == 0 && blank) {
			jumpCount++;
		}
		if (currentColor == savedColor && currentColor.alpha != 0) {
			writeCount++;
		}
		if (currentColor != savedColor && currentColor.alpha == 0) {
			jumpCount++;
			blank = true;
		}
		if (endline || (currentColor != savedColor && currentColor.alpha != 0)) {
			savedColor.print();
			sbuff_push_back(&instructions, Instruction{writeCount, jumpCount, savedColor, endline});
			savedColor = Color(currentColor);
			//NSLog(@"")
			writeCount = 1;
			jumpCount = 0;
			blank = false;
		}


		index += 4;	
	} while (index+4 < image.width * image.height);

	CompressedImage test = CompressedImage{image.height, image.width, static_cast<uint32>(instructions.length), instructions.data};

	return CompressedImage{image.height, image.width, static_cast<uint32>(instructions.length), instructions.data};
}

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
	double min = numeric_limits<double>::max();
	for(int i = 0; i < n; i++) {
		min = nums[i] < min && nums[i] >= lowBound ? nums[i] : min;
	}
	//NSLog(@"min: %f", min);
	return min;
}

internal double bounded2Min(double nums[], int n, double lowBound) {
	double min = numeric_limits<double>::max();
	double min2 = numeric_limits<double>::max();
	for(int i = 0; i < n; i++) {
		if (nums[i] < min && nums[i] >= lowBound) {
			min2 = min;
			min = nums[i];
		} else if (nums[i] < min2 && nums[i] >= lowBound) {
			min2 = nums[i];}
	}
	//NSLog(@"min2: %f", min2);
	return min2;
}

internal void flatBottomTriangle(Position p1, Position p2, Position p3, Color c) {
	if (p1.y < p2.y) {Position temp = p1; p1 = p2; p2 = temp;}
	if (p1.y < p3.y) {Position temp = p1; p1 = p3; p3 = temp;}
	if (p2.x > p3.x) {Position temp = p2; p2 = p3; p3 = temp;}
	double yMax = p1.y;
	double closeSlope = Position::slope(p1, p2);
	double farSlope = Position::slope(p1, p3);

	uint8_t *row = (uint8_t *)buffer;
	row += pitch * (int)yMax;
	for(int curY = yMax; curY >= p2.y; curY--) {
		int startX = (int) ((curY - p1.y) / closeSlope + p1.x);
		int endX = (int) ((curY - p1.y) / farSlope + p1.x);
		uint8_t *pixelChannel = (uint8_t *)row;
		pixelChannel += max(startX, 0)*4;
		for(int curX = startX; curX <= endX; curX++) {
			memcpy(pixelChannel, &c, sizeof(Color));
			pixelChannel+=4; }
		row -= pitch;
	}
}

internal void flatTopTriangle(Position p1, Position p2, Position p3, Color c) {
	if (p1.y > p2.y) {Position temp = p1; p1 = p2; p2 = temp;}
	if (p1.y > p3.y) {Position temp = p1; p1 = p3; p3 = temp;}
	if (p2.x > p3.x) {Position temp = p2; p2 = p3; p3 = temp;}
	double yMin = p1.y;
	double closeSlope = Position::slope(p1, p2);
	double farSlope = Position::slope(p1, p3);

	uint8_t *row = (uint8_t *)buffer;
	row += pitch * (int)yMin;
	for(int curY = yMin; curY <= p2.y; curY++) {
		int startX = (int) ((curY - p1.y) / closeSlope + p1.x);
		int endX = (int) ((curY - p1.y) / farSlope + p1.x);
		uint8_t *pixelChannel = (uint8_t *)row;
		pixelChannel += max(startX, 0)*4;
		for(int curX = startX; curX <= endX; curX++) {
			memcpy(pixelChannel, &c, sizeof(Color));
			pixelChannel+=4; }
		row += pitch;
	}
}

internal void drawTriangle(Position p1, Position p2, Position p3, Color c) {
	if (p2.y < p3.y) {Position temp = p2; p2 = p3; p3 = temp;}
	if (p1.y > p2.y) {Position temp = p1; p1 = p2; p2 = temp;}
	if (p1.y < p3.y) {Position temp = p1; p1 = p3; p3 = temp;}
	double slope = Position::slope(p2, p3);

	Position point = {(p1.y - p2.y) / slope + p2.x, p1.y};
	flatTopTriangle(p1, p3, point, Red);
	flatBottomTriangle(p1, p2, point, Red);
}

// draws a circle ... wow
internal void drawCircle(Position p, int r, Color c) {
	int width = bitmapWidth;
	int height = bitmapHeight;
	uint8_t *row = (uint8_t *)buffer;
	int posY = (int)p.y;
	int posX = (int)p.x;
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
	int posY = (int)p.y;
 	int posX = (int)p.x;
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
internal void drawCircleWithHole(Position center, double radius, Color color, int currentHealth, int maxHealth) {
	int width = bitmapWidth;
	int height = bitmapHeight;
	uint8_t *row = (uint8_t *)buffer;
	int posY = (int)center.y;
	int posX = (int)center.x;
	int r2 = radius * radius;

	row += max(posY-radius, 0) * pitch;
	for(int y = max(posY-radius, 0); y < min(posY+radius, height); ++y) {

		uint8_t *pixelChannel = (uint8_t *)row;
		pixelChannel+= max(posX-radius, 0)*4;
		for(int x = max(posX-radius, 0); x < min(posX+radius, width); ++x) {
			
			//Red
			double length = Position(posX-x, posY-y).length();
			double l2 = (posX-x)*(posX-x) + (posY-y) * (posY - y);
			double holeRadius = (maxHealth-currentHealth)/(double)maxHealth * radius;
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

const uint16 CIRCLE_SHAPE = 0;
const uint16 RECTANGLE_SHAPE = 1;
const uint16 REGULAR_POLYGON_SHAPE = 2;
const uint16 CONVEX_POLYGON_SHAPE = 3;

struct Shape {

	//UNIVERSAL
	uint16 SHAPE_CODE;
	Position center;
	Color color;

	//CIRCLE ONLY
	double radius;

	//POLYGON ONLY
	Position *positions;
	int sides;

	Shape() {};

	Shape(Position center, double radius, Color color) {
		this-> SHAPE_CODE = CIRCLE_SHAPE;
		this-> center = center;
		this-> radius = radius;
		this-> color = color;
	}

	Shape(Position p1, Position p2, Color color) {
		this-> SHAPE_CODE = RECTANGLE_SHAPE;
		Position pos[] = {p1, Position(p1.x, p2.y), p2, Position(p2.x, p1.y)};
		this-> center = Position((p1.x + p2.x)/2.0, (p1.y + p2.y)/2.0);
		this-> positions = pos;
		this-> sides = 4;
		this-> color = color;
	}

	Shape(int sides, Position *positions, Color color) {
		this-> SHAPE_CODE = CONVEX_POLYGON_SHAPE;
		this-> positions = positions;
		this-> color = color;
		this-> sides = sides;
		double xPos = 0;
		double yPos = 0;
		for(int n = 0; n < sides; n++) {
			xPos += positions[n].x;
			yPos += positions[n].y;
		}
		this-> center = {xPos/sides, yPos/sides};
	}

	void draw() {
		if (SHAPE_CODE == CIRCLE_SHAPE) {
			drawCircle(center, radius, color);
		}
		else {
			for(int n = 0; n < sides-1; n++) {
					drawTriangle(center, positions[n], positions[n+1], color);
			} drawTriangle(center, positions[0], positions[sides-1], color);
		}
	}

	void drawRotating(double rpm) {
		if(SHAPE_CODE == CIRCLE_SHAPE) {
			drawCircle(center, radius, color);
			return;
		}
		Position last = {center.x + (double)radius * cos(frames/(600.0/rpm)), center.y + (double)radius * sin(frames/(600.0/rpm))};
		double step = TWO_PI/sides;
		double offset = step + atan2((last.y-center.y), (last.x-center.x));
		for(double theta = offset; theta < TWO_PI + offset; theta += step) {
			Position next = {center.x + radius * cos(theta), center.y + radius * sin(theta)};
			drawTriangle(center, last, next, color);
			last = next;
		}
	}

	void draw(int currentHealth, int maxHealth) {
		if (currentHealth == 0) {
			return;
		}
		if (SHAPE_CODE == CIRCLE_SHAPE) {
			drawCircleWithHole(center, radius, color, currentHealth, maxHealth);
		}
		else { 
				//TODO: fix this in the actual logic;
				currentHealth = maxHealth - currentHealth;
				for(int n = 0; n < sides-1; n++) {
					drawTriangle(positions[n], positions[n+1], Position{(positions[n].x-center.x)*currentHealth/maxHealth+center.x, (positions[n].y-center.y)*currentHealth/maxHealth+center.y}, color);
					drawTriangle(positions[n+1], Position{(positions[n].x-center.x)*currentHealth/maxHealth+center.x, (positions[n].y-center.y)*currentHealth/maxHealth+center.y}, Position{(positions[n+1].x-center.x)*currentHealth/maxHealth+center.x, (positions[n+1].y-center.y)*currentHealth/maxHealth+center.y}, color);
					//Position a[] = {positions[n], positions[n+1], Position{(positions[n].x-center.x)*curHP/maxHP+center.x, (positions[n].y-center.y)*curHP/maxHP+center.y}, Position{(positions[n+1].x-center.x)*curHP/maxHP+center.x, (positions[n+1].y-center.y)*curHP/maxHP+center.y}};
					//TODO TODO TODO mqthy math math math
					//ConvexNgon{4, a, color, rpm}.draw();
				}
				drawTriangle(positions[0], positions[sides-1], Position{(positions[0].x-center.x)*currentHealth/maxHealth+center.x, (positions[0].y-center.y)*currentHealth/maxHealth+center.y}, color);
				drawTriangle(positions[sides-1], Position{(positions[0].x-center.x)*currentHealth/maxHealth+center.x, (positions[0].y-center.y)*currentHealth/maxHealth+center.y}, Position{(positions[sides-1].x-center.x)*currentHealth/maxHealth+center.x, (positions[sides-1].y-center.y)*currentHealth/maxHealth+center.y}, color);
		}
	}

	bool touch(Position pos) {

		if (SHAPE_CODE == CIRCLE_SHAPE) {
			return (center.x - pos.x) * (center.x - pos.x) + (center.y - pos.y) * (center.y - pos.y) <= radius * radius;
		}
		else {
			int intersectCount = 0;
			Position a = positions[sides-1];

			// (y - y1) = m(x - x1)
			for (int n = 0; n < sides; n++) {
				Position b = positions[n];
				//NSLog(@"a: %f %f", a.x, a.y);
				//NSLog(@"b: %f %f", b.x, b.y);
				//NSLog(@"mouse: %f %f", pos.x, pos.y);

				if (a.y == b.y) {
				}
				else if (a.x == b.x) {
					//NSLog(@"%d %d %d", pos.x < a.x, pos.x < b.x, unorderedBetween(a.y, pos.y, b.y));
					if ((pos.x < a.x || pos.x < b.x) && unorderedBetween(a.y, pos.y, b.y)) {
										//NSLog(@"b%d", intersectCount);	
						intersectCount++;
					}
				}
				else {
					double slope = Position::slope(a, positions[n]);
					double intersectX = (pos.y - a.y) / slope + a.x;
					if (pos.x > intersectX && unorderedBetween(a.y, pos.y, b.y)) {
						intersectCount++;
						NSLog(@"%d", n);
						NSLog(@"%f %f", a.x, a.y);
						NSLog(@"%f %f", b.x, b.y);
						NSLog(@"c%d", intersectCount);	
					}
				}
				a = b;
			}

			return intersectCount % 2;
		}
	}
};

static Shape Circle(Position position, double radius, Color color) {
	return Shape(position, radius, color);
}

static Shape ConvexPolygon(int sides, Position *positions, Color color) {
	return Shape(sides, positions, color);
}

static Shape Rectangle(Position a, Position b, Color color) {
	return Shape(a, b, color);
}

struct Thing {

	//UNIVERSAL
	uint16 THING_CODE;
	Shape shape;

	//TURRET AND BULLET
	int team;

	//TURRET ONLY
	int cooldown;
	int currentHealth = 1;
	int maxHealth = 1;
	int framesSinceFired;

	//BULLET ONLY
	Position velocity;
	bool alive;

	Thing() {};

	Thing(int team, Shape shape, int cooldown, int currentHealth, int maxHealth, int framesSinceFired) {
		this-> THING_CODE = TURRET_THING;
		this-> team = team;
		this-> shape = shape;
		this-> cooldown = cooldown;
		this-> currentHealth = currentHealth;
		this-> maxHealth = maxHealth;
		this-> framesSinceFired = framesSinceFired;
	}

	Thing(Shape shape, Position velocity, int team, bool alive) {
		this-> THING_CODE = BULLET_THING;
		this-> shape = shape;
		this-> velocity = velocity;
		this-> team = team;
		this-> alive = alive;
		this-> shape.color = TeamColors[team];
	}

	Thing(Shape shape) {
		this-> THING_CODE = OBJECT_THING;
		this-> shape = shape;
	}

	void draw() {
		if (currentHealth == 0) {
			return;
		}
		else {
			if(maxHealth == currentHealth) {
				shape.draw();
			} else { 
				shape.draw(currentHealth, maxHealth);
			}
		}
	}

	void draw(int currentHealth, int maxHealth) {
		shape.draw(currentHealth, maxHealth);
	}
};

static Thing Turret(int team, Shape shape, int cooldown, int currentHealth, int maxHealth, int framesSinceFired) {
	return Thing(team, shape, cooldown, currentHealth, maxHealth, framesSinceFired);
}

static Thing Bullet(Shape shape, Position velocity, int team) {
	return Thing(shape, velocity, team, true);
}

static Thing Bullet() {
	return Thing(Shape(), Position(), -1, false);
}

// regular polygon
struct RegNgon {
	Position center;
	double radius;
	int sides;
	Color color;
	double rpm;
	double maxHP = 1;
	double curHP = 1;

	RegNgon(Position cen, double rad, int s, Color c, double r) {
		center = cen;
		radius = rad;
		sides = s;
		color = c;
		rpm = r;
	}

	void draw() {
		Position last = {center.x + radius, center.y};
		double step = TWO_PI/sides;
		for(double theta = step; theta < TWO_PI + step; theta += step) {
			Position next = {center.x + radius * cos(theta), center.y + radius * sin(theta)};
			drawTriangle(center, last, next, color);
			last = next;
		}
	}

	void drawRotating() {
		Position last = {center.x + (double)radius * cos(frames/(600.0/rpm)), center.y + (double)radius * sin(frames/(600.0/rpm))};
		double step = TWO_PI/sides;
		double offset = step + atan2((last.y-center.y), (last.x-center.x));
		for(double theta = offset; theta < TWO_PI + offset; theta += step) {
			Position next = {center.x + radius * cos(theta), center.y + radius * sin(theta)};
			drawTriangle(center, last, next, color);
			last = next;
		}
	}
};



/*
	void drawRotating() {
		Position last = {center.x + (double)radius * cos(frames/(600.0/rpm)), center.y + (double)radius * sin(frames/(600.0/rpm))};
		double step = TWO_PI/sides;
		double offset = step + atan2((last.y-center.y), (last.x-center.x));
		for(double theta = offset; theta < TWO_PI + offset; theta += step) {
			Position next = {center.x + radius * cos(theta), center.y + radius * sin(theta)};
			drawTriangle(center, last, next, color);
			last = next;
		}
	}*/


internal void drawRotatingNgon(Position center, int radius, int sides, Color c, double rpm) {
	Position last = {center.x + (double)radius * cos(frames/(600.0/rpm)), center.y + (double)radius * sin(frames/(600.0/rpm))};
	double step = TWO_PI/sides;
    double offset = step + atan2((last.y-center.y), (last.x-center.x));
	for(double theta = offset; theta < TWO_PI + offset; theta += step) {
		Position next = {center.x + radius * cos(theta), center.y + radius * sin(theta)};
		drawTriangle(center, last, next, c);
		last = next;
	}
}

internal void drawNgon(Position center, int radius, int n, Color c) {
	Position last = {center.x + radius, center.y};
	double step = TWO_PI/n;
	for(double theta = step; theta < TWO_PI + step; theta += step) {
		Position next = {center.x + radius * cos(theta), center.y + radius * sin(theta)};
		drawTriangle(center, last, next, c);
		last = next;
	}
}


Thing player;
Thing bullets[1024];
Thing turrets[numTurrets];
Thing objects[numObjects];

bool circleTouch(Position p1, int r1, Position p2, int r2) {
	return (p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y) <= (r1 + r2) * (r1 + r2);}
bool circleTouch(Shape a, Shape b) {
	return circleTouch(a.center, a.radius, b.center, b.radius);}
bool circleTouch(Thing a, Thing b) {
	return circleTouch(a.shape, b.shape);}

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
	else player = Turret(TeamPlayer, Circle(Position(512, 380), 10.0, Blue), 32, 10, 10, 10);
	for (Thing &t: turrets) {
		t.currentHealth = t.maxHealth;
		// = { Position(rand() % (GlobalRenderingWidth-50) +25, rand() % (GlobalRenderingHeight-50)+25), 20, Red, 1, 30, 10, 10 };
	}
}

//fire bullet
void fireBullet(Thing source, Position target) {
	for (Thing &b: bullets) {
		if (!b.alive) {
			b = Bullet(Circle(source.shape.center, 5, TeamColors[source.team]), Position::unitVector(source.shape.center, target).mul(gameSpeed), source.team);
			return;
		}
	}	
}

//bullet updates
void simulateBullets() { 
	for (Thing &b: bullets) {
		if (b.alive) {
			if (between(0-b.shape.radius, b.shape.center.x, bitmapWidth+b.shape.radius) && between(0-b.shape.radius, b.shape.center.y, bitmapHeight+b.shape.radius)) {
				if (b.team != player.team && circleTouch(b, player)) {
					player.currentHealth--;
					b.alive = false;}
				for (Thing &t: turrets) {
					if (t.currentHealth > 0 && b.team != t.team && circleTouch(b, t)) {
						b.alive = false;
						t.currentHealth--;
					}
				}
				b.draw();
				b.shape.center = Position::add(b.shape.center, b.velocity);
			}
			else {
				b.alive = false; }
		}
	}
}

Thing *selected;
Position offset;
Shape scaleCircle;
Shape *vertices;

Thing* getSelected() {
	//NSLog(@"%f, %f", player.shape.center.x, mousePos.x); 
	//NSLog(@"%f, %f", player.shape.center.y - player.radius, mousePos.y); //Position::distance(mousePos, selected -> position - Position{0, static_cast<double>(selected -> shape.radius)}));
	if (selected) {
		if (selected->shape.SHAPE_CODE != CIRCLE_SHAPE) {
			Position previous = selected->shape.positions[selected->shape.sides-1];
			for (int i = 0; i < selected->shape.sides; i++) {
				if (circleTouch(Position::average({previous, selected->shape.positions[i]}), 3, mousePos, 0)){
					return selected;
				}
				previous = selected->shape.positions[i];
			}
		}
		else if (scaleCircle.touch(mousePos)) {
			return selected;
		}

	}
	for (Thing &t: turrets) {
		if (t.shape.touch(mousePos)) {
			return &t;
		}}
	for (Thing &o: objects) {
		if (o.shape.touch(mousePos)) {
			return &o;
		}
	}
	if (player.shape.touch(mousePos)) {
		return &player;
	}
	return NULL;
}

/*
	0 - unselected
	1 - 
*/
uint16 curUse;
Position lastMouse;

void editor() {
	for (Thing t: turrets) {
		t.currentHealth = t.maxHealth;
		t.draw();}
	for (Thing o: objects) {
		o.draw();
	}
	player.draw();

	if (click) {
		curUse = 0;
		selected = getSelected();
		if(selected) {
			offset = selected -> shape.center - mousePos;
			lastMouse = mousePos;
		}
		//NSLog(@"%f", offset.y);
	}

// 				Position change = mousePos - selected -> shape.center + offset;
// 			offset = selected -> shape.center - mousePos;

// mousePos - selected -> shape.center + selected -> shape.center - mousePos;

	if (selected) {
		scaleCircle = Circle(selected -> shape.center - Position{0, static_cast<double>(selected -> shape.radius)}, 3, Green);

		if (selected->shape.SHAPE_CODE != CIRCLE_SHAPE) {
			Position previous = selected->shape.positions[selected->shape.sides-1];
			for (int i = 0; i < selected->shape.sides; i++) {
				Circle(Position::average({previous, selected->shape.positions[i]}), 3, Green).draw();
				previous = selected->shape.positions[i];
			}
		}
		else {
			scaleCircle.draw();
		}

		if (leftMouseButtonDown) {
			int index = -3;
			if (selected->shape.SHAPE_CODE != CIRCLE_SHAPE) {
				Position previous = selected->shape.positions[selected->shape.sides-1];
				for (int i = 0; i < selected->shape.sides; i++) {
					if (circleTouch(Position::average({previous, selected->shape.positions[i]}), 3, mousePos, 0)){
						//NSLog(@"%d %d", i, index);
						index = i;
					}
					previous = selected->shape.positions[i];
				}
			}
			// what the fuck is this variable idk how it works
			Position change = mousePos - lastMouse;
			NSLog(@"%f %f %f %f", mousePos.x, mousePos.y, selected -> shape.center.x, selected -> shape.center.y);
			NSLog(@"%f %f", change.x, change.y);
			if (curUse == 1 || (selected->shape.SHAPE_CODE == CIRCLE_SHAPE && curUse == 0 && scaleCircle.touch(mousePos))) {
				//NSLog(@"wow %f      %f \n %f       %f", mousePos.y, selected -> shape.center.y, selected -> shape.radius, offset.y);
				selected -> shape.radius = selected -> shape.center.y - mousePos.y;
				curUse = 1;
			} else if (curUse == 2 || (curUse == 0 && index != -3)) {
				double xPos = 0;
				double yPos = 0;
				int sides = selected->shape.sides;
				// need to find change in direction perpindicular to line
				//NSLog(@"Before: %f %f", selected->shape.positions[index].x, selected->shape.positions[index].y);
				selected->shape.positions[index] += change;
				selected->shape.positions[(index-1)%sides] += change;
				//NSLog(@"After: %f %f", selected->shape.positions[index].x, selected->shape.positions[index].y);
				for(int n = 0; n < sides; n++) {
					xPos += selected->shape.positions[n].x;
					yPos += selected->shape.positions[n].y;
					//NSLog(@"%f %f", selected->shape.positions[n].x, selected->shape.positions[n].y);
				}
				selected->shape.center = {xPos/sides, yPos/sides};
				//NSLog(@"%f %f", selected->shape.center.x, selected->shape.center.y);


				curUse = 2;
			}
			// moving the shape
			else {
				curUse = 3;
				selected -> shape.center += change;
				if (selected->shape.SHAPE_CODE != CIRCLE_SHAPE) {
					for (int i = 0; i < selected->shape.sides; i++) {
						selected->shape.positions[i] += change;
					}
				}	
				NSLog(@"Change: %f %f", change.x, change.y);
			}
			lastMouse = mousePos;
			//NSLog(@"this should work");
		}
	}
	//selected.color = Red;

}

// turret updates
void simulateTurrets() {
	for (Thing &t: turrets) {
		if (t.currentHealth > 0){
			t.draw();
			if (t.framesSinceFired++ > t.cooldown) {
				fireBullet(t, player.shape.center);
				t.framesSinceFired = 0;}
		}
	}
}

// checks to see if need reset
void checkGameState() {
	if (player.currentHealth <= 0) startup();
	for (Thing &t: turrets) {
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

void updatePlayer() {
	// upadtes player position based on buttons pressed	
	Position playerV = { 0, 0 };	
	if (keyPressed[wKeyCode]) {playerV.y-=10;}
	if (keyPressed[sKeyCode]) {playerV.y+=10;}
	if (keyPressed[aKeyCode]) {playerV.x-=10;}
	if (keyPressed[dKeyCode]) {playerV.x+=10;}
	if (playerV.length() != 0)
		player.shape.center.add( { playerV.unitVector().x * gameSpeed,  playerV.unitVector().y * gameSpeed});
	player.shape.center.x = min(player.shape.center.x, bitmapWidth);
	player.shape.center.x = max(player.shape.center.x, 0);
	player.shape.center.y = min(player.shape.center.y, bitmapHeight);
	player.shape.center.y = max(player.shape.center.y, 0);

	player.draw();
	if (click || leftMouseButtonDown) {
		fireBullet(player, mousePos);
	}
}

void game() {
	simulateBullets();
	simulateTurrets();
	updatePlayer();
	checkGameState();
}


int main(int args, const char * argv[]) {
	//vector<int> g1;
	//g1.push_back(2);

	Position b[] = {Position{200, 200}, Position{200, 100}, Position{100, 100}, Position{100, 200}, Position{150, 250}};
	Position a[] = {Position{200, 200}, Position{100, 100}, Position{300, 100}};
	player = Turret(TeamPlayer, Circle(Position(512, 380), 10.0, Blue), 32, 10, 10, 10);
	for (Thing &t: turrets) {
		Position p = Position(rand() % (GlobalRenderingWidth-50) +25, rand() % (GlobalRenderingHeight-50)+25);
		t = Turret(TeamEnemy, Circle(p, 20.0, Red), 30, 10, 10, 0);
	}
	objects[0] = ConvexPolygon(5, b, Red);
	//objects[0].draw(1, 2);


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

	uint8_t save[20*20*4];
	//for (int i = 0; i < 20*20; i++) 
	memset(save, (uint8_t)255, 20*20*4);
	//memset(save, (uint8_t)100, 10*20*4);
	//memset(save, (uint8_t)200, 5*20*4);
	BasicImage startScreen = BasicImage{20, 20, save};

	CompressedImage test = convertBasicToCompressed(startScreen);
	test.print();

    uint64_t lastCounter = mach_absolute_time();  

	//main run loop
	while (Running) {

		click = false;

		NSEvent* event;
		leftMouseButtonDown = false;	
    
	    do {
			//checks event list for key and mouse events
			event = [NSApp nextEventMatchingMask: NSEventMaskAny
					untilDate: nil
					inMode: NSDefaultRunLoopMode
					dequeue: YES];
			switch ([event type]) {
				case NSEventTypeKeyDown:
					keyPressed[event.keyCode] = true;
					keyHeld[event.keyCode] = !keyHeld[event.keyCode];
					if (event.keyCode == qKeyCode) { Running = false;}
					[NSApp sendEvent: event];
					break;
				case NSEventTypeKeyUp:
					keyPressed[event.keyCode] = false;
					[NSApp sendEvent: event];
					break;
				case NSEventTypeLeftMouseDown:
                    mousePos = { event.locationInWindow.x, -(event.locationInWindow.y-760) };
					click = true;
					//NSLog(@"down");
					break;
				case NSEventTypeLeftMouseDragged:
                    mousePos = { event.locationInWindow.x, -(event.locationInWindow.y-760) };
					break;
				default:
					[NSApp sendEvent: event];
				NSUInteger mouseButtonMask = [NSEvent pressedMouseButtons];
				if(!leftMouseButtonDown) {
					leftMouseButtonDown = (mouseButtonMask & (1 << 0)) != 0;}


				// TODO: actually get mouse holding to work
				/*if (leftMouseButtonDown) {
					if (!((mousePos.x == 0 && mousePos.y == 760) || (mousePos.x == 0 && mousePos.y == 0))) {
						mousePos = { event.locationInWindow.x, -(event.locationInWindow.y-760) }; }

					NSLog(@"mouse x: %f \n mouse y: %f", mousePos.x, mousePos.y);
					fireBullet(player, mousePos);
				}  */



			}	
		} while (event != nil);
						if (leftMouseButtonDown) {
					//NSLog(@"mouse down");
				}


		//updating game objects
		clearScreen();

		//flatBottomTriangle(Position{200, 200}, Position{100, 100}, Position{300, 100}, Red);
		//flatTopTriangle(Position{200, 200}, Position{100, 300}, Position{300, 300}, Red);
		//drawTriangle(Position{200, 200}, Position{300, 150}, Position{100, 100}, Red);
		//NSLog(@"%f", abs(sin(frames/(600.0/30))));

		ConvexPolygon(5, b, Red).draw(abs(sin(frames/(600.0/30))*100), 100);
		objects[0].draw(1, 2);
		if (keyHeld[eKeyCode]) {
			editor();
			//test.draw(Position(512, 380));
		}
		else {
			game();
		}

		uint64_t counter1 = mach_absolute_time();
		//drawNgon(Position{512, 370}, 50, 40, Red);
		uint64_t counter2 = mach_absolute_time();
		//NSLog(@"Fast?? Circle: %llu", (counter2-counter1));

		uint64_t counter3 = mach_absolute_time();
		//drawTurret( Turret{Position{312, 370}, 50, Red, 1, 40, 5, 10, 200});
		uint64_t counter4 = mach_absolute_time();
		//NSLog(@"Normal Circle: %llu", (counter4 - counter3));
	
		

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

        //NSLog(@"Frames Per Second: %f", framesPerSecond);

		frames++;
        lastCounter = mach_absolute_time();

		macGetSecondsElapsed(&timeBase, lastCounter, workCounter);

		// 	
		macOSRedrawBuffer(Window);
	}

	printf("Twinstick Finished Building"); 
}
