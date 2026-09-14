import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' hide Hmac;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'identity_service.dart';
import 'secure_storage_service.dart';

final mnemonicServiceProvider = Provider((ref) {
  final identityService = ref.watch(identityServiceProvider);
  return MnemonicService(
    identityService,
    // The backup marker MUST live in the same keychain
    // SecurityOverviewService reads — the shared SecureStorageService.
    storage: ref.watch(secureStorageServiceProvider),
    // A recovery replaces the stored identity out-of-band: force the
    // identity cache to reload so getIdentity() can never serve the
    // pre-recovery keypair (split-brain). Wired here — by construction —
    // so no UI call site can forget it.
    onIdentityRecovered: identityService.reloadIdentity,
  );
});

/// BIP-39 English wordlist — the complete, official 2048-word list,
/// vendored verbatim (one word per line, in BIP-39 index order) from
/// https://github.com/bitcoin/bips/blob/master/bip-0039/english.txt
/// which is public domain (CC0-1.0 / MIT-licensed BIP text).
const String _bip39WordlistText = '''
abandon
ability
able
about
above
absent
absorb
abstract
absurd
abuse
access
accident
account
accuse
achieve
acid
acoustic
acquire
across
act
action
actor
actress
actual
adapt
add
addict
address
adjust
admit
adult
advance
advice
aerobic
affair
afford
afraid
again
age
agent
agree
ahead
aim
air
airport
aisle
alarm
album
alcohol
alert
alien
all
alley
allow
almost
alone
alpha
already
also
alter
always
amateur
amazing
among
amount
amused
analyst
anchor
ancient
anger
angle
angry
animal
ankle
announce
annual
another
answer
antenna
antique
anxiety
any
apart
apology
appear
apple
approve
april
arch
arctic
area
arena
argue
arm
armed
armor
army
around
arrange
arrest
arrive
arrow
art
artefact
artist
artwork
ask
aspect
assault
asset
assist
assume
asthma
athlete
atom
attack
attend
attitude
attract
auction
audit
august
aunt
author
auto
autumn
average
avocado
avoid
awake
aware
away
awesome
awful
awkward
axis
baby
bachelor
bacon
badge
bag
balance
balcony
ball
bamboo
banana
banner
bar
barely
bargain
barrel
base
basic
basket
battle
beach
bean
beauty
because
become
beef
before
begin
behave
behind
believe
below
belt
bench
benefit
best
betray
better
between
beyond
bicycle
bid
bike
bind
biology
bird
birth
bitter
black
blade
blame
blanket
blast
bleak
bless
blind
blood
blossom
blouse
blue
blur
blush
board
boat
body
boil
bomb
bone
bonus
book
boost
border
boring
borrow
boss
bottom
bounce
box
boy
bracket
brain
brand
brass
brave
bread
breeze
brick
bridge
brief
bright
bring
brisk
broccoli
broken
bronze
broom
brother
brown
brush
bubble
buddy
budget
buffalo
build
bulb
bulk
bullet
bundle
bunker
burden
burger
burst
bus
business
busy
butter
buyer
buzz
cabbage
cabin
cable
cactus
cage
cake
call
calm
camera
camp
can
canal
cancel
candy
cannon
canoe
canvas
canyon
capable
capital
captain
car
carbon
card
cargo
carpet
carry
cart
case
cash
casino
castle
casual
cat
catalog
catch
category
cattle
caught
cause
caution
cave
ceiling
celery
cement
census
century
cereal
certain
chair
chalk
champion
change
chaos
chapter
charge
chase
chat
cheap
check
cheese
chef
cherry
chest
chicken
chief
child
chimney
choice
choose
chronic
chuckle
chunk
churn
cigar
cinnamon
circle
citizen
city
civil
claim
clap
clarify
claw
clay
clean
clerk
clever
click
client
cliff
climb
clinic
clip
clock
clog
close
cloth
cloud
clown
club
clump
cluster
clutch
coach
coast
coconut
code
coffee
coil
coin
collect
color
column
combine
come
comfort
comic
common
company
concert
conduct
confirm
congress
connect
consider
control
convince
cook
cool
copper
copy
coral
core
corn
correct
cost
cotton
couch
country
couple
course
cousin
cover
coyote
crack
cradle
craft
cram
crane
crash
crater
crawl
crazy
cream
credit
creek
crew
cricket
crime
crisp
critic
crop
cross
crouch
crowd
crucial
cruel
cruise
crumble
crunch
crush
cry
crystal
cube
culture
cup
cupboard
curious
current
curtain
curve
cushion
custom
cute
cycle
dad
damage
damp
dance
danger
daring
dash
daughter
dawn
day
deal
debate
debris
decade
december
decide
decline
decorate
decrease
deer
defense
define
defy
degree
delay
deliver
demand
demise
denial
dentist
deny
depart
depend
deposit
depth
deputy
derive
describe
desert
design
desk
despair
destroy
detail
detect
develop
device
devote
diagram
dial
diamond
diary
dice
diesel
diet
differ
digital
dignity
dilemma
dinner
dinosaur
direct
dirt
disagree
discover
disease
dish
dismiss
disorder
display
distance
divert
divide
divorce
dizzy
doctor
document
dog
doll
dolphin
domain
donate
donkey
donor
door
dose
double
dove
draft
dragon
drama
drastic
draw
dream
dress
drift
drill
drink
drip
drive
drop
drum
dry
duck
dumb
dune
during
dust
dutch
duty
dwarf
dynamic
eager
eagle
early
earn
earth
easily
east
easy
echo
ecology
economy
edge
edit
educate
effort
egg
eight
either
elbow
elder
electric
elegant
element
elephant
elevator
elite
else
embark
embody
embrace
emerge
emotion
employ
empower
empty
enable
enact
end
endless
endorse
enemy
energy
enforce
engage
engine
enhance
enjoy
enlist
enough
enrich
enroll
ensure
enter
entire
entry
envelope
episode
equal
equip
era
erase
erode
erosion
error
erupt
escape
essay
essence
estate
eternal
ethics
evidence
evil
evoke
evolve
exact
example
excess
exchange
excite
exclude
excuse
execute
exercise
exhaust
exhibit
exile
exist
exit
exotic
expand
expect
expire
explain
expose
express
extend
extra
eye
eyebrow
fabric
face
faculty
fade
faint
faith
fall
false
fame
family
famous
fan
fancy
fantasy
farm
fashion
fat
fatal
father
fatigue
fault
favorite
feature
february
federal
fee
feed
feel
female
fence
festival
fetch
fever
few
fiber
fiction
field
figure
file
film
filter
final
find
fine
finger
finish
fire
firm
first
fiscal
fish
fit
fitness
fix
flag
flame
flash
flat
flavor
flee
flight
flip
float
flock
floor
flower
fluid
flush
fly
foam
focus
fog
foil
fold
follow
food
foot
force
forest
forget
fork
fortune
forum
forward
fossil
foster
found
fox
fragile
frame
frequent
fresh
friend
fringe
frog
front
frost
frown
frozen
fruit
fuel
fun
funny
furnace
fury
future
gadget
gain
galaxy
gallery
game
gap
garage
garbage
garden
garlic
garment
gas
gasp
gate
gather
gauge
gaze
general
genius
genre
gentle
genuine
gesture
ghost
giant
gift
giggle
ginger
giraffe
girl
give
glad
glance
glare
glass
glide
glimpse
globe
gloom
glory
glove
glow
glue
goat
goddess
gold
good
goose
gorilla
gospel
gossip
govern
gown
grab
grace
grain
grant
grape
grass
gravity
great
green
grid
grief
grit
grocery
group
grow
grunt
guard
guess
guide
guilt
guitar
gun
gym
habit
hair
half
hammer
hamster
hand
happy
harbor
hard
harsh
harvest
hat
have
hawk
hazard
head
health
heart
heavy
hedgehog
height
hello
helmet
help
hen
hero
hidden
high
hill
hint
hip
hire
history
hobby
hockey
hold
hole
holiday
hollow
home
honey
hood
hope
horn
horror
horse
hospital
host
hotel
hour
hover
hub
huge
human
humble
humor
hundred
hungry
hunt
hurdle
hurry
hurt
husband
hybrid
ice
icon
idea
identify
idle
ignore
ill
illegal
illness
image
imitate
immense
immune
impact
impose
improve
impulse
inch
include
income
increase
index
indicate
indoor
industry
infant
inflict
inform
inhale
inherit
initial
inject
injury
inmate
inner
innocent
input
inquiry
insane
insect
inside
inspire
install
intact
interest
into
invest
invite
involve
iron
island
isolate
issue
item
ivory
jacket
jaguar
jar
jazz
jealous
jeans
jelly
jewel
job
join
joke
journey
joy
judge
juice
jump
jungle
junior
junk
just
kangaroo
keen
keep
ketchup
key
kick
kid
kidney
kind
kingdom
kiss
kit
kitchen
kite
kitten
kiwi
knee
knife
knock
know
lab
label
labor
ladder
lady
lake
lamp
language
laptop
large
later
latin
laugh
laundry
lava
law
lawn
lawsuit
layer
lazy
leader
leaf
learn
leave
lecture
left
leg
legal
legend
leisure
lemon
lend
length
lens
leopard
lesson
letter
level
liar
liberty
library
license
life
lift
light
like
limb
limit
link
lion
liquid
list
little
live
lizard
load
loan
lobster
local
lock
logic
lonely
long
loop
lottery
loud
lounge
love
loyal
lucky
luggage
lumber
lunar
lunch
luxury
lyrics
machine
mad
magic
magnet
maid
mail
main
major
make
mammal
man
manage
mandate
mango
mansion
manual
maple
marble
march
margin
marine
market
marriage
mask
mass
master
match
material
math
matrix
matter
maximum
maze
meadow
mean
measure
meat
mechanic
medal
media
melody
melt
member
memory
mention
menu
mercy
merge
merit
merry
mesh
message
metal
method
middle
midnight
milk
million
mimic
mind
minimum
minor
minute
miracle
mirror
misery
miss
mistake
mix
mixed
mixture
mobile
model
modify
mom
moment
monitor
monkey
monster
month
moon
moral
more
morning
mosquito
mother
motion
motor
mountain
mouse
move
movie
much
muffin
mule
multiply
muscle
museum
mushroom
music
must
mutual
myself
mystery
myth
naive
name
napkin
narrow
nasty
nation
nature
near
neck
need
negative
neglect
neither
nephew
nerve
nest
net
network
neutral
never
news
next
nice
night
noble
noise
nominee
noodle
normal
north
nose
notable
note
nothing
notice
novel
now
nuclear
number
nurse
nut
oak
obey
object
oblige
obscure
observe
obtain
obvious
occur
ocean
october
odor
off
offer
office
often
oil
okay
old
olive
olympic
omit
once
one
onion
online
only
open
opera
opinion
oppose
option
orange
orbit
orchard
order
ordinary
organ
orient
original
orphan
ostrich
other
outdoor
outer
output
outside
oval
oven
over
own
owner
oxygen
oyster
ozone
pact
paddle
page
pair
palace
palm
panda
panel
panic
panther
paper
parade
parent
park
parrot
party
pass
patch
path
patient
patrol
pattern
pause
pave
payment
peace
peanut
pear
peasant
pelican
pen
penalty
pencil
people
pepper
perfect
permit
person
pet
phone
photo
phrase
physical
piano
picnic
picture
piece
pig
pigeon
pill
pilot
pink
pioneer
pipe
pistol
pitch
pizza
place
planet
plastic
plate
play
please
pledge
pluck
plug
plunge
poem
poet
point
polar
pole
police
pond
pony
pool
popular
portion
position
possible
post
potato
pottery
poverty
powder
power
practice
praise
predict
prefer
prepare
present
pretty
prevent
price
pride
primary
print
priority
prison
private
prize
problem
process
produce
profit
program
project
promote
proof
property
prosper
protect
proud
provide
public
pudding
pull
pulp
pulse
pumpkin
punch
pupil
puppy
purchase
purity
purpose
purse
push
put
puzzle
pyramid
quality
quantum
quarter
question
quick
quit
quiz
quote
rabbit
raccoon
race
rack
radar
radio
rail
rain
raise
rally
ramp
ranch
random
range
rapid
rare
rate
rather
raven
raw
razor
ready
real
reason
rebel
rebuild
recall
receive
recipe
record
recycle
reduce
reflect
reform
refuse
region
regret
regular
reject
relax
release
relief
rely
remain
remember
remind
remove
render
renew
rent
reopen
repair
repeat
replace
report
require
rescue
resemble
resist
resource
response
result
retire
retreat
return
reunion
reveal
review
reward
rhythm
rib
ribbon
rice
rich
ride
ridge
rifle
right
rigid
ring
riot
ripple
risk
ritual
rival
river
road
roast
robot
robust
rocket
romance
roof
rookie
room
rose
rotate
rough
round
route
royal
rubber
rude
rug
rule
run
runway
rural
sad
saddle
sadness
safe
sail
salad
salmon
salon
salt
salute
same
sample
sand
satisfy
satoshi
sauce
sausage
save
say
scale
scan
scare
scatter
scene
scheme
school
science
scissors
scorpion
scout
scrap
screen
script
scrub
sea
search
season
seat
second
secret
section
security
seed
seek
segment
select
sell
seminar
senior
sense
sentence
series
service
session
settle
setup
seven
shadow
shaft
shallow
share
shed
shell
sheriff
shield
shift
shine
ship
shiver
shock
shoe
shoot
shop
short
shoulder
shove
shrimp
shrug
shuffle
shy
sibling
sick
side
siege
sight
sign
silent
silk
silly
silver
similar
simple
since
sing
siren
sister
situate
six
size
skate
sketch
ski
skill
skin
skirt
skull
slab
slam
sleep
slender
slice
slide
slight
slim
slogan
slot
slow
slush
small
smart
smile
smoke
smooth
snack
snake
snap
sniff
snow
soap
soccer
social
sock
soda
soft
solar
soldier
solid
solution
solve
someone
song
soon
sorry
sort
soul
sound
soup
source
south
space
spare
spatial
spawn
speak
special
speed
spell
spend
sphere
spice
spider
spike
spin
spirit
split
spoil
sponsor
spoon
sport
spot
spray
spread
spring
spy
square
squeeze
squirrel
stable
stadium
staff
stage
stairs
stamp
stand
start
state
stay
steak
steel
stem
step
stereo
stick
still
sting
stock
stomach
stone
stool
story
stove
strategy
street
strike
strong
struggle
student
stuff
stumble
style
subject
submit
subway
success
such
sudden
suffer
sugar
suggest
suit
summer
sun
sunny
sunset
super
supply
supreme
sure
surface
surge
surprise
surround
survey
suspect
sustain
swallow
swamp
swap
swarm
swear
sweet
swift
swim
swing
switch
sword
symbol
symptom
syrup
system
table
tackle
tag
tail
talent
talk
tank
tape
target
task
taste
tattoo
taxi
teach
team
tell
ten
tenant
tennis
tent
term
test
text
thank
that
theme
then
theory
there
they
thing
this
thought
three
thrive
throw
thumb
thunder
ticket
tide
tiger
tilt
timber
time
tiny
tip
tired
tissue
title
toast
tobacco
today
toddler
toe
together
toilet
token
tomato
tomorrow
tone
tongue
tonight
tool
tooth
top
topic
topple
torch
tornado
tortoise
toss
total
tourist
toward
tower
town
toy
track
trade
traffic
tragic
train
transfer
trap
trash
travel
tray
treat
tree
trend
trial
tribe
trick
trigger
trim
trip
trophy
trouble
truck
true
truly
trumpet
trust
truth
try
tube
tuition
tumble
tuna
tunnel
turkey
turn
turtle
twelve
twenty
twice
twin
twist
two
type
typical
ugly
umbrella
unable
unaware
uncle
uncover
under
undo
unfair
unfold
unhappy
uniform
unique
unit
universe
unknown
unlock
until
unusual
unveil
update
upgrade
uphold
upon
upper
upset
urban
urge
usage
use
used
useful
useless
usual
utility
vacant
vacuum
vague
valid
valley
valve
van
vanish
vapor
various
vast
vault
vehicle
velvet
vendor
venture
venue
verb
verify
version
very
vessel
veteran
viable
vibrant
vicious
victory
video
view
village
vintage
violin
virtual
virus
visa
visit
visual
vital
vivid
vocal
voice
void
volcano
volume
vote
voyage
wage
wagon
wait
walk
wall
walnut
want
warfare
warm
warrior
wash
wasp
waste
water
wave
way
wealth
weapon
wear
weasel
weather
web
wedding
weekend
weird
welcome
west
wet
whale
what
wheat
wheel
when
where
whip
whisper
wide
width
wife
wild
will
win
window
wine
wing
wink
winner
winter
wire
wisdom
wise
wish
witness
wolf
woman
wonder
wood
wool
word
work
world
worry
worth
wrap
wreck
wrestle
wrist
write
wrong
yard
year
yellow
you
young
youth
zebra
zero
zone
zoo
''';

/// The decoded wordlist: exactly 2048 entries, index-aligned with BIP-39.
final List<String> _bip39Wordlist =
    List<String>.unmodifiable(_bip39WordlistText.trim().split('\n'));

/// Reverse lookup (word -> BIP-39 index) for validation/decoding.
final Map<String, int> _bip39Index = {
  for (var i = 0; i < _bip39Wordlist.length; i++) _bip39Wordlist[i]: i,
};

/// Result of mnemonic generation
class MnemonicResult {
  final List<String> words;
  final Uint8List entropy;
  final Uint8List seed;

  MnemonicResult({
    required this.words,
    required this.entropy,
    required this.seed,
  });

  /// Get the mnemonic as a space-separated string
  String get phrase => words.join(' ');

  /// Word count (should be 24 for 256-bit entropy)
  int get wordCount => words.length;
}

/// Service for BIP-39 mnemonic backup and recovery.
///
/// TRUST MODEL — entropy source: an Alexandria identity is an Ed25519
/// keypair whose stored private key IS a 32-byte seed. A backup phrase
/// therefore encodes that seed directly as BIP-39 entropy
/// (ENT = 256 bits -> 24 words). This intentionally deviates from the
/// usual BIP-39 -> PBKDF2 -> BIP-32 HD-wallet chain: there is no HD
/// tree in Alexandria, so the mnemonic *is* the private key, protected
/// by the standard BIP-39 checksum. Recovery decodes the phrase back to
/// entropy and uses it verbatim as the Ed25519 seed, guaranteeing that
/// backup -> recover yields the SAME public key.
///
/// The PBKDF2-HMAC-SHA512 seed derivation is still computed onto
/// [MnemonicResult.seed] for API compatibility, but it is not used on
/// the recover path (using it would break the round-trip, since PBKDF2
/// output cannot be inverted back to the original key).
class MnemonicService {
  final IdentityService _identityService;

  /// Shared secure store for the backup marker. This MUST be the same
  /// [SecureStorageService] instance/keychain that
  /// `SecurityOverviewService` reads — previously this was a bare
  /// `const FlutterSecureStorage()`, which uses a DIFFERENT macOS
  /// keychain (no `usesDataProtectionKeychain: false`), so the marker
  /// written here was invisible to the security alerts.
  final SecureStorageService _storage;
  final _random = Random.secure();

  static const int _pbkdf2Iterations = 2048;

  /// Legal BIP-39 entropy lengths in bytes (128..256 bits, 32-bit steps).
  static const List<int> _validEntropyBytes = [16, 20, 24, 28, 32];

  /// Legal BIP-39 word counts (one 11-bit word per 32+1 entropy bits).
  static const Set<int> _validWordCounts = {12, 15, 18, 21, 24};

  /// Optional hook invoked after [recoverFromMnemonic] successfully
  /// replaces the stored identity. The provider wires this to
  /// [IdentityService.reloadIdentity] so no stale identity survives in
  /// any cache — enforced by construction so UI call sites can't
  /// forget it.
  final Future<void> Function()? onIdentityRecovered;

  MnemonicService(
    this._identityService, {
    required SecureStorageService storage,
    this.onIdentityRecovered,
  }) : _storage = storage;

  /// Generate a new 24-word mnemonic from 256-bit entropy
  Future<MnemonicResult> generateMnemonic() async {
    // 1. Generate 256 bits of secure random entropy
    final entropy = Uint8List(32); // 256 bits = 32 bytes
    for (var i = 0; i < entropy.length; i++) {
      entropy[i] = _random.nextInt(256);
    }

    // 2. Encode entropy (+ BIP-39 checksum) as words
    final words = _entropyToWords(entropy);

    // 3. Derive seed using PBKDF2 (retained for API compatibility)
    final seed = await _mnemonicToSeed(words, '');

    return MnemonicResult(words: words, entropy: entropy, seed: seed);
  }

  /// Convert entropy bytes to mnemonic words.
  ///
  /// Standard BIP-39 encoding: ENT || CS, where CS is the first
  /// ENT/32 bits of SHA-256(entropy), split into 11-bit groups that
  /// index the official 2048-word list.
  List<String> _entropyToWords(Uint8List entropy) {
    assert(
      _validEntropyBytes.contains(entropy.length),
      'BIP-39 entropy must be 128-256 bits in 32-bit steps',
    );

    final checksumBitCount = entropy.length * 8 ~/ 32; // CS = ENT/32
    final hash = sha256.convert(entropy);
    final hashBits = hash.bytes
        .map((b) => b.toRadixString(2).padLeft(8, '0'))
        .join();

    final bits = StringBuffer();
    for (final byte in entropy) {
      bits.write(byte.toRadixString(2).padLeft(8, '0'));
    }
    bits.write(hashBits.substring(0, checksumBitCount));

    final bitString = bits.toString();
    final words = <String>[];
    for (var i = 0; i + 11 <= bitString.length; i += 11) {
      final index = int.parse(bitString.substring(i, i + 11), radix: 2);
      words.add(_bip39Wordlist[index]);
    }
    return words;
  }

  /// Decode mnemonic words back to raw entropy bytes (inverse of
  /// [_entropyToWords]). Assumes [words] passed [validateMnemonic].
  Uint8List _wordsToEntropy(List<String> words) {
    final bits = StringBuffer();
    for (final word in words) {
      bits.write(_bip39Index[word.toLowerCase()]!
          .toRadixString(2)
          .padLeft(11, '0'));
    }
    final bitString = bits.toString();
    final entropyBitCount = bitString.length * 32 ~/ 33;

    final entropy = Uint8List(entropyBitCount ~/ 8);
    for (var i = 0; i < entropyBitCount; i += 8) {
      entropy[i ~/ 8] =
          int.parse(bitString.substring(i, i + 8), radix: 2);
    }
    return entropy;
  }

  /// Derive seed from mnemonic using PBKDF2-HMAC-SHA512
  Future<Uint8List> _mnemonicToSeed(
    List<String> words,
    String passphrase,
  ) async {
    final mnemonic = words.join(' ');
    final salt = 'mnemonic$passphrase';

    // Use PBKDF2 with HMAC-SHA512
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha512(),
      iterations: _pbkdf2Iterations,
      bits: 512,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(mnemonic)),
      nonce: utf8.encode(salt),
    );

    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Validate a mnemonic phrase: every word must be a real BIP-39
  /// English word, the word count must be a legal BIP-39 length
  /// (12/15/18/21/24), and the embedded SHA-256 checksum must match.
  bool validateMnemonic(List<String> words) {
    if (!_validWordCounts.contains(words.length)) return false;

    // Check all words are in the real wordlist and build index list
    final indices = <int>[];
    for (final word in words) {
      final index = _bip39Index[word.toLowerCase()];
      if (index == null) return false;
      indices.add(index);
    }

    // Convert word indices to bits (11 bits per word)
    final bitString = StringBuffer();
    for (final index in indices) {
      bitString.write(index.toRadixString(2).padLeft(11, '0'));
    }
    final bits = bitString.toString();

    // ENT = total*32/33 bits; the remainder is the checksum
    final entropyBitCount = bits.length * 32 ~/ 33;
    final checksumBitCount = bits.length - entropyBitCount;

    // Convert entropy bits to bytes
    final entropyBytes = <int>[];
    for (var i = 0; i < entropyBitCount; i += 8) {
      entropyBytes.add(int.parse(bits.substring(i, i + 8), radix: 2));
    }

    // Compute expected checksum from entropy
    final hash = sha256.convert(entropyBytes);
    final hashBits =
        hash.bytes.map((b) => b.toRadixString(2).padLeft(8, '0')).join();
    final expectedChecksum = hashBits.substring(0, checksumBitCount);

    // Verify checksum matches
    return bits.substring(entropyBitCount) == expectedChecksum;
  }

  /// Generate identity from mnemonic.
  ///
  /// The decoded entropy is used directly as the Ed25519 private-key
  /// seed (see class docs): for a 24-word phrase the 32-byte entropy IS
  /// the key, so recovering a phrase produced by [backupCurrentIdentity]
  /// restores the exact same public key. Shorter standard entropies
  /// (12/15/18/21 words) are expanded to a 32-byte seed via SHA-256.
  ///
  /// The recovered identity is persisted through
  /// [IdentityService.importIdentity] so the write lands in the SAME
  /// storage [IdentityService.getIdentity] reads AND the in-memory
  /// identity cache is refreshed atomically. Afterwards
  /// [onIdentityRecovered] is invoked (wired by the provider to
  /// [IdentityService.reloadIdentity]) as belt-and-suspenders cache
  /// coherency. Previously this wrote the storage keys directly and
  /// never touched IdentityService's cache, so getIdentity() kept
  /// serving the OLD keypair while storage held the recovered one.
  Future<AlexandriaIdentity?> recoverFromMnemonic(List<String> words) async {
    if (!validateMnemonic(words)) {
      return null;
    }

    // Decode entropy from the phrase; Ed25519 seeds are 32 bytes.
    final entropy = _wordsToEntropy(words);
    final privateKeySeed = entropy.length == 32
        ? entropy
        : Uint8List.fromList(sha256.convert(entropy).bytes);

    // Derive the keypair and persist through IdentityService — the
    // single owner of the identity keys and their cache.
    final identity = await _identityService.importIdentity(privateKeySeed);

    // The identity is already persisted and cached; a failing hook must
    // not turn a successful recovery into a reported failure.
    final onRecovered = onIdentityRecovered;
    if (onRecovered != null) {
      try {
        await onRecovered();
      } catch (e, stackTrace) {
        developer.log(
          'onIdentityRecovered hook threw after a successful recovery',
          name: 'MnemonicService',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    return identity;
  }

  /// Backup current identity as mnemonic.
  ///
  /// The phrase is DERIVED FROM the stored private key — it encodes the
  /// identity's own 32-byte Ed25519 seed as BIP-39 entropy, so
  /// [recoverFromMnemonic] restores the same keypair and public key.
  /// (Previously this generated a fresh random mnemonic, which meant the
  /// "backup" silently recovered a DIFFERENT identity.)
  ///
  /// For identities whose stored key is not a standard BIP-39 entropy
  /// length (e.g. an imported raw key of unusual size), the key bytes
  /// are reduced to 256-bit entropy via SHA-256. In that case recovery
  /// restores the keypair derived from SHA-256(privateKey), which
  /// cannot equal the original key — a documented limitation; such
  /// identities should be re-seeded through
  /// [IdentityService.generateIdentity].
  Future<MnemonicResult?> backupCurrentIdentity() async {
    final identity = await _identityService.getIdentity();
    if (identity == null) return null;

    final entropy = _validEntropyBytes.contains(identity.privateKey.length)
        ? identity.privateKey
        : Uint8List.fromList(sha256.convert(identity.privateKey).bytes);

    final words = _entropyToWords(entropy);
    final seed = await _mnemonicToSeed(words, '');
    return MnemonicResult(words: words, entropy: entropy, seed: seed);
  }

  /// Record that the user has confirmed saving the recovery phrase.
  ///
  /// The marker is a SHA-256 of the phrase (never the phrase itself),
  /// written to the shared [SecureStorageService] store under
  /// [SecureStorageKeys.mnemonicBackup] — the same key and keychain
  /// `SecurityOverviewService` checks before warning about a missing
  /// backup. This is deliberately a separate step from
  /// [backupCurrentIdentity]: the marker is written on explicit user
  /// confirmation ("I've saved it"), not when the phrase is merely
  /// derived and displayed.
  ///
  /// `IdentityService` clears this marker whenever the stored keypair
  /// is replaced (import/rotate/delete), since the old phrase can no
  /// longer recover the new key.
  ///
  /// The write is delegated to [IdentityService.markMnemonicBackupConfirmed]
  /// so it lands inside the same serialized op-chain as identity
  /// mutations: a confirmation racing an [IdentityService.importIdentity]
  /// cannot resurrect a stale marker. Additionally, when [phrase] is a
  /// decodable BIP-39 phrase, the public key it recovers is derived and
  /// passed along — the marker is then written only while that key is
  /// still the stored one, so the outcome is independent of the
  /// serialized order.
  Future<void> markBackupConfirmed(String phrase) async {
    final phraseHash = sha256.convert(utf8.encode(phrase));
    final phraseHashHex = _hexEncode(Uint8List.fromList(phraseHash.bytes));

    // Best-effort: determine which public key this phrase recovers.
    // If the phrase doesn't decode, the marker write is still
    // serialized (ordering with the clearing writes applies), just
    // without the staleness check.
    String? expectedPublicKeyHex;
    final words =
        phrase.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (validateMnemonic(words)) {
      try {
        final entropy = _wordsToEntropy(words);
        final seed = entropy.length == 32
            ? entropy
            : Uint8List.fromList(sha256.convert(entropy).bytes);
        final keyPair = await Ed25519().newKeyPairFromSeed(seed);
        final publicKey = await keyPair.extractPublicKey();
        expectedPublicKeyHex =
            _hexEncode(Uint8List.fromList(publicKey.bytes));
      } catch (_) {
        expectedPublicKeyHex = null;
      }
    }

    await _identityService.markMnemonicBackupConfirmed(
      phraseHashHex,
      expectedPublicKeyHex: expectedPublicKeyHex,
    );
  }

  /// Check if a backup exists
  Future<bool> hasBackup() async {
    return await _storage.containsKey(SecureStorageKeys.mnemonicBackup);
  }

  // Helper: Hex encode
  String _hexEncode(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
