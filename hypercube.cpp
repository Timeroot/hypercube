// hypercube.cpp - an interpreter for the hypercube language.
// Build: g++ -std=c++17 -O2 -o hypercube hypercube.cpp

#include <algorithm>
#include <cctype>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace hc {

// A Fail stops one part of the program. A block handler can catch a Fail.
struct Fail : std::runtime_error {
    explicit Fail(const std::string& m) : std::runtime_error(m) {}
};
// A Fatal stops the interpreter. No handler catches a Fatal.
struct Fatal : std::runtime_error {
    explicit Fatal(const std::string& m) : std::runtime_error(m) {}
};
struct SrcError : std::runtime_error {
    explicit SrcError(const std::string& m) : std::runtime_error(m) {}
};

// ------------------------------------------------------------------
// The memory. A cube with n inds holds 2^n bits.
// The first ind is the most significant bit of the array index.
// The left half of a cube is the first half of the array.
// ------------------------------------------------------------------

struct Cube {
    int dims = 0;
    std::vector<uint8_t> b;
};

static Cube fillCube(int dims, uint8_t v) {
    Cube c;
    c.dims = dims;
    c.b.assign(size_t(1) << dims, v);
    return c;
}

static bool allFalse(const Cube& c) {
    for (uint8_t v : c.b)
        if (v) return false;
    return true;
}

static bool allTrue(const Cube& c) {
    for (uint8_t v : c.b)
        if (!v) return false;
    return true;
}

// ------------------------------------------------------------------
// The syntax tree
// ------------------------------------------------------------------

enum class Op { Nand, Dup, Split, Block, Recur, Call, Seq };

struct Node {
    Op op;
    // Seq: the items in source order. Split: {left, right}. Block: {body, handler}.
    std::vector<Node*> kids;
    Node* target = nullptr;   // Recur: the block to run.
    int def = -1;             // Call: the index in the definition table.
    int amps = 0;             // Recur: the number of ampersand characters.
    std::string name;         // Call: the name in the source.
    bool hasHandler = false;  // Block: true if the source gives a handler.
    int line = 0;
};

struct Arena {
    std::vector<std::unique_ptr<Node>> nodes;
    Node* make(Op op, int line) {
        nodes.push_back(std::make_unique<Node>());
        Node* n = nodes.back().get();
        n->op = op;
        n->line = line;
        return n;
    }
};

static std::string show(const Node* n) {
    switch (n->op) {
        case Op::Nand: return "@";
        case Op::Dup: return "=";
        case Op::Split: return "(" + show(n->kids[0]) + "," + show(n->kids[1]) + ")";
        case Op::Block:
            return "[" + show(n->kids[0]) + (n->hasHandler ? ("," + show(n->kids[1])) : "") + "]";
        case Op::Recur: return "#" + std::string(size_t(n->amps), '&');
        case Op::Call: return n->name;
        case Op::Seq: {
            std::string s;
            for (size_t i = 0; i < n->kids.size(); i++) {
                if (i) s += " ";
                s += show(n->kids[i]);
            }
            return s;
        }
    }
    return "?";
}

// ------------------------------------------------------------------
// The tokenizer
// ------------------------------------------------------------------

struct Tok {
    enum K { Nand, Dup, LPar, RPar, Comma, LBrk, RBrk, Recur, Ident, Assign, End } k;
    std::string text;
    int amps = 0;
    int line = 1;
};

static std::string atLine(int line) { return "line " + std::to_string(line) + ": "; }

// A new line ends a statement only outside of brackets.
static std::vector<Tok> tokenize(const std::string& src) {
    std::vector<Tok> out;
    int line = 1, depth = 0;
    size_t i = 0;
    auto push = [&](Tok::K k) {
        Tok t;
        t.k = k;
        t.line = line;
        out.push_back(t);
    };
    while (i < src.size()) {
        char ch = src[i];
        if (ch == '\n') {
            if (depth == 0 && !out.empty() && out.back().k != Tok::End) push(Tok::End);
            line++;
            i++;
            continue;
        }
        if (isspace(static_cast<unsigned char>(ch))) { i++; continue; }
        if (ch == ';') {
            while (i < src.size() && src[i] != '\n') i++;
            continue;
        }
        if (ch == '@') { push(Tok::Nand); i++; continue; }
        if (ch == '(') { depth++; push(Tok::LPar); i++; continue; }
        if (ch == ')') { depth--; push(Tok::RPar); i++; continue; }
        if (ch == '[') { depth++; push(Tok::LBrk); i++; continue; }
        if (ch == ']') { depth--; push(Tok::RBrk); i++; continue; }
        if (ch == ',') { push(Tok::Comma); i++; continue; }
        if (ch == ':') {
            if (i + 1 < src.size() && src[i + 1] == '=') { push(Tok::Assign); i += 2; continue; }
            throw SrcError(atLine(line) + "a colon must be part of :=");
        }
        if (ch == '=') { push(Tok::Dup); i++; continue; }
        if (ch == '#') {
            Tok t;
            t.k = Tok::Recur;
            t.line = line;
            i++;
            while (i < src.size() && src[i] == '&') { t.amps++; i++; }
            out.push_back(t);
            continue;
        }
        if (isalpha(static_cast<unsigned char>(ch)) || ch == '_') {
            size_t s = i;
            while (i < src.size() &&
                   (isalnum(static_cast<unsigned char>(src[i])) || src[i] == '_'))
                i++;
            Tok t;
            t.k = Tok::Ident;
            t.text = src.substr(s, i - s);
            t.line = line;
            out.push_back(t);
            continue;
        }
        throw SrcError(atLine(line) + "bad character " + std::string(1, ch));
    }
    if (!out.empty() && out.back().k != Tok::End) push(Tok::End);
    return out;
}

// ------------------------------------------------------------------
// The parser
// ------------------------------------------------------------------

struct Parser {
    const std::vector<Tok>& t;
    size_t i = 0;
    Arena& a;
    std::vector<Node*> blocks;  // The open blocks. The innermost block is last.

    Parser(const std::vector<Tok>& toks, Arena& arena) : t(toks), a(arena) {}

    int line() const { return i < t.size() ? t[i].line : (t.empty() ? 1 : t.back().line); }

    bool at(Tok::K k) const { return i < t.size() && t[i].k == k; }

    void expect(Tok::K k, const char* what) {
        if (!at(k)) throw SrcError(atLine(line()) + "expected " + what);
        i++;
    }

    Node* parseSeq() {
        std::vector<Node*> items;
        int startLine = line();
        while (i < t.size() && !at(Tok::RPar) && !at(Tok::RBrk) && !at(Tok::Comma))
            items.push_back(parseItem());
        if (items.size() == 1) return items[0];
        Node* n = a.make(Op::Seq, startLine);
        n->kids = items;
        return n;
    }

    Node* parseItem() {
        const Tok tk = t[i];
        switch (tk.k) {
            case Tok::Nand: i++; return a.make(Op::Nand, tk.line);
            case Tok::Dup: i++; return a.make(Op::Dup, tk.line);
            case Tok::LPar: {
                i++;
                Node* n = a.make(Op::Split, tk.line);
                Node* l = parseSeq();
                expect(Tok::Comma, "a comma inside the parentheses");
                Node* r = parseSeq();
                expect(Tok::RPar, "a right parenthesis");
                n->kids = {l, r};
                return n;
            }
            case Tok::LBrk: {
                i++;
                Node* n = a.make(Op::Block, tk.line);
                blocks.push_back(n);
                Node* body = parseSeq();
                Node* handler = nullptr;
                if (at(Tok::Comma)) {
                    i++;
                    handler = parseSeq();
                    n->hasHandler = true;
                }
                expect(Tok::RBrk, "a right square bracket");
                blocks.pop_back();
                n->kids.push_back(body);
                n->kids.push_back(handler ? handler : a.make(Op::Seq, tk.line));
                return n;
            }
            case Tok::Recur: {
                i++;
                if (size_t(tk.amps) >= blocks.size())
                    throw SrcError(atLine(tk.line) + "this # needs " +
                                   std::to_string(tk.amps + 1) + " enclosing blocks, but " +
                                   std::to_string(blocks.size()) + " blocks are open");
                Node* n = a.make(Op::Recur, tk.line);
                n->amps = tk.amps;
                n->target = blocks[blocks.size() - 1 - size_t(tk.amps)];
                return n;
            }
            case Tok::Ident: {
                i++;
                Node* n = a.make(Op::Call, tk.line);
                n->name = tk.text;
                return n;
            }
            case Tok::Assign:
                throw SrcError(atLine(tk.line) +
                               "the := sign is only valid after the first name of a statement");
            default: throw SrcError(atLine(tk.line) + "unexpected token");
        }
    }
};

struct Def {
    std::string name;
    Node* body = nullptr;
    int line = 0;
};

struct Program {
    Arena arena;
    std::vector<Def> defs;
    std::vector<Node*> mains;  // The statements that have no name.
    std::map<std::string, int> index;
};

static void resolveCalls(Program& p, Node* n) {
    if (n->op == Op::Call) {
        auto it = p.index.find(n->name);
        if (it == p.index.end())
            throw SrcError(atLine(n->line) + "unknown name " + n->name);
        n->def = it->second;
        return;
    }
    for (Node* k : n->kids)
        if (k) resolveCalls(p, k);
}

static void parseProgram(Program& p, const std::string& src) {
    std::vector<Tok> toks = tokenize(src);
    size_t s = 0;
    while (s < toks.size()) {
        size_t e = s;
        while (e < toks.size() && toks[e].k != Tok::End) e++;
        std::vector<Tok> stmt(toks.begin() + s, toks.begin() + e);
        s = e + 1;
        if (stmt.empty()) continue;

        std::string name;
        int declLine = stmt[0].line;
        if (stmt.size() >= 2 && stmt[0].k == Tok::Ident && stmt[1].k == Tok::Assign) {
            name = stmt[0].text;
            stmt.erase(stmt.begin(), stmt.begin() + 2);
        }
        Parser ps(stmt, p.arena);
        Node* body = ps.parseSeq();
        if (ps.i != stmt.size())
            throw SrcError(atLine(ps.line()) + "an extra right parenthesis or bracket is here");

        if (name.empty()) {
            p.mains.push_back(body);
        } else {
            if (p.index.count(name))
                throw SrcError(atLine(declLine) + "the name " + name + " has two definitions");
            p.index[name] = int(p.defs.size());
            p.defs.push_back(Def{name, body, declLine});
        }
    }
    for (Def& d : p.defs) resolveCalls(p, d.body);
    for (Node* m : p.mains) resolveCalls(p, m);
}

// ------------------------------------------------------------------
// The expander: one program without names
// ------------------------------------------------------------------
// Every name becomes its body. A # counts brackets, not definitions, and a
// definition can never hold a # without its own brackets. Therefore the
// substitution never changes the block that a # names.
// Every character of the language is one token, so the result needs no
// space between the parts.
// A name that calls itself through other names cannot expand, because the
// text would have no end. The expander reports such a name, and the program
// must use # for that loop.

struct Expander {
    const Program& p;
    std::vector<long long> memo;
    std::vector<int> color;  // 0 not seen, 1 in progress, 2 complete

    explicit Expander(const Program& prog)
        : p(prog), memo(prog.defs.size(), -1), color(prog.defs.size(), 0) {}

    long long size(const Node* n) {
        switch (n->op) {
            case Op::Nand:
            case Op::Dup: return 1;
            case Op::Recur: return 1 + n->amps;
            case Op::Split: return size(n->kids[0]) + size(n->kids[1]) + 3;
            case Op::Block:
                return size(n->kids[0]) + (n->hasHandler ? size(n->kids[1]) + 1 : 0) + 2;
            case Op::Seq: {
                long long s = 0;
                for (Node* k : n->kids) s += size(k);
                return s;
            }
            case Op::Call: return defSize(n->def);
        }
        return 0;
    }

    long long defSize(int i) {
        size_t k = size_t(i);
        if (color[k] == 1)
            throw SrcError("the name " + p.defs[k].name +
                           " calls itself through the names, so the program cannot"
                           " expand; use # for that loop");
        if (color[k] == 2) return memo[k];
        color[k] = 1;
        long long s = size(p.defs[k].body);
        color[k] = 2;
        memo[k] = s;
        return s;
    }

    void emit(const Node* n, std::string& out) {
        switch (n->op) {
            case Op::Nand: out += '@'; return;
            case Op::Dup: out += '='; return;
            case Op::Recur:
                out += '#';
                out.append(size_t(n->amps), '&');
                return;
            case Op::Split:
                out += '(';
                emit(n->kids[0], out);
                out += ',';
                emit(n->kids[1], out);
                out += ')';
                return;
            case Op::Block:
                out += '[';
                emit(n->kids[0], out);
                if (n->hasHandler) {
                    out += ',';
                    emit(n->kids[1], out);
                }
                out += ']';
                return;
            case Op::Seq:
                for (Node* k : n->kids) emit(k, out);
                return;
            case Op::Call: emit(p.defs[size_t(n->def)].body, out); return;
        }
    }
};

// ------------------------------------------------------------------
// The evaluator
// ------------------------------------------------------------------

struct Ctx {
    const std::vector<Def>* defs = nullptr;
    bool pad = false;
    bool trace = false;
    int maxDims = 24;
    int maxDepth = 100000;
    int depth = 0;
    int tdepth = 0;
    long long nodes = 0;   // the number of program parts that ran
    long long nands = 0;   // the number of @ operations
    long long bitops = 0;  // the number of NAND operations on one bit
};

struct DepthGuard {
    Ctx& c;
    explicit DepthGuard(Ctx& ctx) : c(ctx) {
        if (++c.depth > c.maxDepth) {
            --c.depth;
            throw Fatal("the program is at the call depth limit of " +
                        std::to_string(c.maxDepth));
        }
    }
    ~DepthGuard() { --c.depth; }
};

struct TraceGuard {
    Ctx& c;
    TraceGuard(Ctx& ctx, const Node* n, const Cube& x, const char* tag) : c(ctx) {
        if (c.trace) {
            std::string s = show(n);
            if (s.size() > 44) s = s.substr(0, 41) + "...";
            fprintf(stderr, "%*s%s %s | inds=%d\n", 2 * c.tdepth, "", tag, s.c_str(), x.dims);
        }
        c.tdepth++;
    }
    ~TraceGuard() { c.tdepth--; }
};

static Cube nandOp(Ctx& c, const Cube& x) {
    if (x.dims == 0) throw Fail("the @ operation needs a cube with at least one ind");
    size_t h = x.b.size() / 2;
    c.nands++;
    c.bitops += (long long)h;
    Cube r;
    r.dims = x.dims - 1;
    r.b.resize(h);
    for (size_t k = 0; k < h; k++) r.b[k] = uint8_t(!(x.b[k] & x.b[k + h]));
    return r;
}

static Cube dupOp(Ctx& c, const Cube& x) {
    if (x.dims >= c.maxDims)
        throw Fatal("the cube is larger than the limit of " + std::to_string(c.maxDims) +
                    " inds");
    Cube r;
    r.dims = x.dims + 1;
    r.b.reserve(x.b.size() * 2);
    r.b.insert(r.b.end(), x.b.begin(), x.b.end());
    r.b.insert(r.b.end(), x.b.begin(), x.b.end());
    return r;
}

static void halves(const Cube& x, Cube& l, Cube& r) {
    size_t h = x.b.size() / 2;
    l.dims = x.dims - 1;
    l.b.assign(x.b.begin(), x.b.begin() + h);
    r.dims = x.dims - 1;
    r.b.assign(x.b.begin() + h, x.b.end());
}

// The two halves of a split must have the same number of inds.
static void matchDims(Ctx& c, Cube& l, Cube& r) {
    if (l.dims == r.dims) return;
    if (!c.pad)
        throw Fail("the halves of a split have different inds: " + std::to_string(l.dims) +
                   " and " + std::to_string(r.dims));
    while (l.dims < r.dims) l = dupOp(c, l);
    while (r.dims < l.dims) r = dupOp(c, r);
}

static Cube joinCubes(Ctx& c, Cube l, Cube r) {
    if (l.dims >= c.maxDims)
        throw Fatal("the cube is larger than the limit of " + std::to_string(c.maxDims) +
                    " inds");
    Cube o;
    o.dims = l.dims + 1;
    o.b = std::move(l.b);
    o.b.insert(o.b.end(), r.b.begin(), r.b.end());
    return o;
}

static Cube eval(Ctx& c, const Node* n, Cube x);

// This function makes the @ operation lazy. It runs the left part first.
// If the left result holds only false bits, the right part is not necessary,
// because NAND(false, y) is always true.
static Cube lazyNand(Ctx& c, const Node* n, Cube x) {
    switch (n->op) {
        case Op::Seq: {
            if (n->kids.empty()) return nandOp(c, x);
            for (size_t k = n->kids.size(); k > 1; k--)
                x = eval(c, n->kids[k - 1], std::move(x));
            return lazyNand(c, n->kids[0], std::move(x));
        }
        case Op::Call: {
            DepthGuard g(c);
            return lazyNand(c, (*c.defs)[size_t(n->def)].body, std::move(x));
        }
        case Op::Recur: {
            DepthGuard g(c);
            return lazyNand(c, n->target, std::move(x));
        }
        case Op::Block: {
            DepthGuard g(c);
            if (!n->hasHandler) return lazyNand(c, n->kids[0], std::move(x));
            Cube saved = x;
            try {
                return lazyNand(c, n->kids[0], std::move(x));
            } catch (Fail&) {
                return lazyNand(c, n->kids[1], std::move(saved));
            }
        }
        case Op::Split: {
            TraceGuard tg(c, n, x, "lazy @");
            if (x.dims == 0) throw Fail("a split needs a cube with at least one ind");
            Cube xl, xr;
            halves(x, xl, xr);
            x.b.clear();
            x.b.shrink_to_fit();
            Cube l = eval(c, n->kids[0], std::move(xl));
            c.nands++;
            c.bitops += (long long)l.b.size();
            if (allFalse(l)) return fillCube(l.dims, 1);  // The right part is not run.
            Cube r = eval(c, n->kids[1], std::move(xr));
            matchDims(c, l, r);
            Cube o;
            o.dims = l.dims;
            o.b.resize(l.b.size());
            for (size_t k = 0; k < l.b.size(); k++) o.b[k] = uint8_t(!(l.b[k] & r.b[k]));
            return o;
        }
        default: return nandOp(c, eval(c, n, std::move(x)));
    }
}

static Cube eval(Ctx& c, const Node* n, Cube x) {
    c.nodes++;
    switch (n->op) {
        case Op::Nand: {
            TraceGuard tg(c, n, x, "run");
            return nandOp(c, x);
        }
        case Op::Dup: {
            TraceGuard tg(c, n, x, "run");
            return dupOp(c, x);
        }
        case Op::Seq: {
            TraceGuard tg(c, n, x, "run");
            size_t k = n->kids.size();
            while (k > 0) {
                // A @ operation before a part starts a lazy NAND.
                if (k >= 2 && n->kids[k - 2]->op == Op::Nand) {
                    x = lazyNand(c, n->kids[k - 1], std::move(x));
                    k -= 2;
                } else {
                    x = eval(c, n->kids[k - 1], std::move(x));
                    k -= 1;
                }
            }
            return x;
        }
        case Op::Split: {
            TraceGuard tg(c, n, x, "run");
            if (x.dims == 0) throw Fail("a split needs a cube with at least one ind");
            Cube xl, xr;
            halves(x, xl, xr);
            x.b.clear();
            x.b.shrink_to_fit();
            Cube l = eval(c, n->kids[0], std::move(xl));
            Cube r = eval(c, n->kids[1], std::move(xr));
            matchDims(c, l, r);
            return joinCubes(c, std::move(l), std::move(r));
        }
        case Op::Block: {
            TraceGuard tg(c, n, x, "run");
            DepthGuard g(c);
            // A block without a handler part does not catch a failure.
            if (!n->hasHandler) return eval(c, n->kids[0], std::move(x));
            Cube saved = x;
            try {
                return eval(c, n->kids[0], std::move(x));
            } catch (Fail&) {
                return eval(c, n->kids[1], std::move(saved));
            }
        }
        case Op::Recur: {
            TraceGuard tg(c, n, x, "run");
            DepthGuard g(c);
            return eval(c, n->target, std::move(x));
        }
        case Op::Call: {
            TraceGuard tg(c, n, x, "run");
            DepthGuard g(c);
            return eval(c, (*c.defs)[size_t(n->def)].body, std::move(x));
        }
    }
    throw Fatal("the node type is unknown");
}

// ------------------------------------------------------------------
// Input and output
// ------------------------------------------------------------------

static Cube parseInput(const std::string& s, int maxDims) {
    std::string bits;
    for (char ch : s) {
        if (isspace(static_cast<unsigned char>(ch)) || ch == '_' || ch == ',') continue;
        if (ch == '0' || ch == '1') { bits += ch; continue; }
        if (ch == 'F' || ch == 'f') { bits += '0'; continue; }
        if (ch == 'T' || ch == 't') { bits += '1'; continue; }
        throw SrcError("the input has a bad character " + std::string(1, ch));
    }
    if (bits.empty()) throw SrcError("the input is empty");
    int dims = 0;
    while ((size_t(1) << dims) < bits.size()) dims++;
    if ((size_t(1) << dims) != bits.size())
        throw SrcError("the input length must be a power of 2, but the length is " +
                       std::to_string(bits.size()));
    if (dims > maxDims) throw SrcError("the input has more inds than the limit");
    Cube c;
    c.dims = dims;
    c.b.resize(bits.size());
    for (size_t i = 0; i < bits.size(); i++) c.b[i] = uint8_t(bits[i] == '1');
    return c;
}

static void nested(const Cube& c, size_t off, int dims, std::string& out) {
    if (dims == 0) {
        out += c.b[off] ? '1' : '0';
        return;
    }
    size_t half = size_t(1) << (dims - 1);
    out += '(';
    nested(c, off, dims - 1, out);
    out += ',';
    nested(c, off + half, dims - 1, out);
    out += ')';
}

static std::string readFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) throw SrcError("the interpreter cannot read the file " + path);
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

// ------------------------------------------------------------------
// The IO interface
// ------------------------------------------------------------------
// A source file that starts with the line IO uses this interface.
// The interpreter runs the program again and again. The first cube is one
// false bit. The program gives one of these three forms back:
//
//   (0,x)         the program is complete; x is the return value
//   (1,(0,y))     read one byte; the program starts again with (1,(byte,y))
//   (1,((1,a),y)) write the 8 low bits of a; the program starts again with (1,y)
//
// The byte from a read has zeros above the 8 low bits. At the end of the
// input the interpreter gives a cube with bit 8 true and all other bits
// false. If the cube for the byte holds 8 bits or less, the end of the input
// gives all false bits.

static bool ioHeader(std::string& src) {
    size_t i = 0;
    while (i < src.size()) {
        size_t e = src.find('\n', i);
        if (e == std::string::npos) e = src.size();
        std::string line = src.substr(i, e - i);
        size_t a = line.find_first_not_of(" \t\r");
        if (a == std::string::npos) {  // a blank line
            i = e + 1;
            continue;
        }
        if (line[a] == ';') {  // a comment line
            i = e + 1;
            continue;
        }
        size_t b = line.find_last_not_of(" \t\r");
        if (line.substr(a, b - a + 1) == "IO") {
            src.erase(i, e - i);  // The line number of the next line stays the same.
            return true;
        }
        return false;
    }
    return false;
}

static void runIo(Ctx& c, const Node* start, bool stats) {
    Cube cube = fillCube(0, 0);  // The program starts with one false bit.
    long long steps = 0, reads = 0, writes = 0;
    for (;;) {
        Cube r = eval(c, start, std::move(cube));
        steps++;
        if (r.dims == 0)
            throw Fail("an IO program must give a cube with at least one ind");
        Cube tag, rest;
        halves(r, tag, rest);
        if (allFalse(tag)) {
            fflush(stdout);
            if (stats)
                fprintf(stderr, "io: complete; %lld steps, %lld reads, %lld writes\n",
                        steps, reads, writes);
            return;
        }
        if (!allTrue(tag))
            throw Fail("the first half of the result must be all true or all false");
        if (rest.dims == 0) throw Fail("a request needs at least one more ind");
        Cube x, y;
        halves(rest, x, y);
        if (allFalse(x)) {
            fflush(stdout);
            int ch = fgetc(stdin);
            Cube b = fillCube(x.dims, 0);
            if (ch == EOF) {
                if (b.b.size() > 8) b.b[8] = 1;
            } else {
                for (size_t k = 0; k < 8 && k < b.b.size(); k++)
                    b.b[k] = uint8_t((ch >> k) & 1);
            }
            reads++;
            Cube inner = joinCubes(c, std::move(b), std::move(y));
            cube = joinCubes(c, fillCube(inner.dims, 1), std::move(inner));
        } else {
            if (x.dims == 0) throw Fail("a write request needs the form (1,a)");
            Cube one, a;
            halves(x, one, a);
            if (!allTrue(one))
                throw Fail("a request must be 0 to read, or (1,a) to write");
            int byte = 0;
            for (size_t k = 0; k < 8 && k < a.b.size(); k++)
                if (a.b[k]) byte |= 1 << k;
            fputc(byte, stdout);
            fflush(stdout);  // The output goes out at once, not at the end.
            writes++;
            cube = joinCubes(c, fillCube(y.dims, 1), std::move(y));
        }
    }
}

static const char* kUsage =
    "usage: hypercube [options] [file.hc ...]\n"
    "\n"
    "  -e, --expr SRC     use SRC as source text\n"
    "  -i, --input BITS   the start cube, as 0 and 1 characters; use - for stdin\n"
    "  -d, --inds N       a start cube of N inds with all bits false\n"
    "      --entry NAME   run this definition\n"
    "      --pad          pad a short split half with = instead of a failure\n"
    "      --nested       also print the result in the ((a,b),(c,d)) form\n"
    "      --trace        print each step to stderr\n"
    "      --raw          print only the result bits\n"
    "      --parse-only   check the syntax, then stop\n"
    "      --stats        print the operation counts to stderr\n"
    "      --no-io        ignore the IO header; run the program one time\n"
    "      --max-inds N   the cube size limit (default 24)\n"
    "      --max-depth N  the call depth limit (default 100000)\n"
    "  -h, --help         print this text\n"
    "\n"
    "The interpreter joins all files and -e texts in the given order.\n"
    "The entry point is the --entry name. If there is no --entry name, it is\n"
    "the last statement without a name. If all statements have names, it is\n"
    "MAIN, or else the last definition.\n";

}  // namespace hc

int main(int argc, char** argv) {
    using namespace hc;
    std::string src, input = "0", entry;
    bool raw = false, showNested = false, parseOnly = false, stats = false;
    bool ioMode = false, noIo = false, expandMode = false;
    long long maxExpand = 64000000;
    Ctx c;

    // Each file and each -e text can start with the IO header.
    auto addSrc = [&](std::string chunk) {
        if (ioHeader(chunk)) ioMode = true;
        src += chunk;
        src += "\n";
    };

    auto need = [&](int& i, const char* what) -> std::string {
        if (i + 1 >= argc) {
            fprintf(stderr, "error: the option %s needs a value\n", what);
            exit(2);
        }
        return argv[++i];
    };

    try {
        for (int i = 1; i < argc; i++) {
            std::string a = argv[i];
            if (a == "-h" || a == "--help") {
                fputs(kUsage, stdout);
                return 0;
            } else if (a == "-e" || a == "--expr") {
                addSrc(need(i, "-e"));
            } else if (a == "-i" || a == "--input") {
                input = need(i, "-i");
            } else if (a == "-d" || a == "--inds") {
                int n = atoi(need(i, "-d").c_str());
                if (n < 0 || n > 24) throw SrcError("the -d value must be from 0 to 24");
                input.assign(size_t(1) << n, '0');
            } else if (a == "--entry") {
                entry = need(i, "--entry");
            } else if (a == "--pad") {
                c.pad = true;
            } else if (a == "--trace") {
                c.trace = true;
            } else if (a == "--nested") {
                showNested = true;
            } else if (a == "--raw") {
                raw = true;
            } else if (a == "--parse-only") {
                parseOnly = true;
            } else if (a == "--stats") {
                stats = true;
            } else if (a == "--no-io") {
                noIo = true;
            } else if (a == "--expand") {
                expandMode = true;
            } else if (a == "--max-expand") {
                maxExpand = atoll(need(i, "--max-expand").c_str());
            } else if (a == "--max-inds") {
                c.maxDims = atoi(need(i, "--max-inds").c_str());
            } else if (a == "--max-depth") {
                c.maxDepth = atoi(need(i, "--max-depth").c_str());
            } else if (a.size() > 1 && a[0] == '-') {
                fprintf(stderr, "error: the option %s is unknown\n", a.c_str());
                return 2;
            } else {
                addSrc(readFile(a));
            }
        }

        if (src.empty()) {
            fputs(kUsage, stderr);
            return 2;
        }

        if (input == "-") {
            std::ostringstream ss;
            ss << std::cin.rdbuf();
            input = ss.str();
        }

        Program p;
        parseProgram(p, src);
        if (parseOnly) {
            printf("ok\n");
            return 0;
        }

        const Node* start = nullptr;
        if (!entry.empty()) {
            auto it = p.index.find(entry);
            if (it == p.index.end())
                throw SrcError("no definition has the name " + entry);
            start = p.defs[size_t(it->second)].body;
        } else if (!p.mains.empty()) {
            start = p.mains.back();
        } else if (p.index.count("MAIN")) {
            start = p.defs[size_t(p.index["MAIN"])].body;
        } else if (!p.defs.empty()) {
            start = p.defs.back().body;
        } else {
            throw SrcError("the source has no statement");
        }

        if (expandMode) {
            Expander ex(p);
            long long chars = ex.size(start);
            fprintf(stderr, "the expanded program has %lld characters\n", chars);
            if (chars > maxExpand) {
                fprintf(stderr,
                        "error: that is more than the limit of %lld characters;"
                        " raise it with --max-expand\n",
                        maxExpand);
                return 3;
            }
            std::string out;
            out.reserve(size_t(chars) + 1);
            ex.emit(start, out);
            printf("%s\n", out.c_str());
            return 0;
        }

        c.defs = &p.defs;

        if (ioMode && !noIo) {
#ifdef _WIN32
            _setmode(_fileno(stdin), _O_BINARY);
            _setmode(_fileno(stdout), _O_BINARY);
#endif
            runIo(c, start, stats);
            if (stats)
                fprintf(stderr, "parts=%lld nand-steps=%lld bit-nands=%lld\n", c.nodes,
                        c.nands, c.bitops);
            return 0;
        }

        Cube x = parseInput(input, c.maxDims);
        Cube y = eval(c, start, std::move(x));

        if (stats)
            fprintf(stderr, "parts=%lld nand-steps=%lld bit-nands=%lld\n", c.nodes,
                    c.nands, c.bitops);
        std::string bits;
        bits.reserve(y.b.size());
        for (uint8_t v : y.b) bits += v ? '1' : '0';
        if (raw) {
            printf("%s\n", bits.c_str());
        } else {
            printf("inds=%d bits=%s\n", y.dims, bits.c_str());
            if (showNested) {
                std::string s;
                nested(y, 0, y.dims, s);
                printf("shape=%s\n", s.c_str());
            }
        }
        return 0;
    } catch (SrcError& e) {
        fprintf(stderr, "source error: %s\n", e.what());
        return 2;
    } catch (Fail& e) {
        fprintf(stderr, "run error: %s\n", e.what());
        return 1;
    } catch (Fatal& e) {
        fprintf(stderr, "fatal error: %s\n", e.what());
        return 3;
    } catch (std::exception& e) {
        fprintf(stderr, "error: %s\n", e.what());
        return 3;
    }
}
