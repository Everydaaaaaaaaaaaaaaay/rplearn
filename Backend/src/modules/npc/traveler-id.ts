export function travelerIdCheckDigit(body: string): number {
  let sum = 0;
  for (
    let sourceIndex = body.length - 1, index = 0;
    sourceIndex >= 0;
    sourceIndex -= 1, index += 1
  ) {
    const digit = body.charCodeAt(sourceIndex) - 48;
    const multiplied = index % 2 === 0 ? digit * 2 : digit;
    sum += multiplied > 9 ? multiplied - 9 : multiplied;
  }
  return (10 - (sum % 10)) % 10;
}

export function isValidTravelerId(value: string): boolean {
  if (!/^[0-9]{11}$/.test(value)) return false;
  return Number(value.at(-1)) === travelerIdCheckDigit(value.slice(0, -1));
}
