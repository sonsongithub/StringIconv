# StringIconv
Decode bytes array to String using iconv.
Foundation.framework does not provide a simple decoding method 
that discards illegal sequence or transliterate unsupported characters. StringIconv provides a feasible method that statisfies the problem.

### case - from Data to String

```
do {
    let data = try Data(contentsOf: urlSourceFile)
    let string = try String.decode(
	     data: data,
	     fromCode: "SHIFT-JIS",
	     discardIllegalSequence: true,
	     transliterate: false
	 )
} catch {
    print(error.localizedDescription)
}
```

### case - from Data to Data

```
do {
    let data = try Data(contentsOf: urlSourceFile)
    let decoded: Data = try String.decode(
        data: data,
        toCode: "UTF8",
        fromCode: "SJIS"
    )
} catch {
    print(error.localizedDescription)
}
```