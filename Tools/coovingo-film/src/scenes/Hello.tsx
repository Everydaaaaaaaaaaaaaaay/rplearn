import { Paper, Headline, NativeScreen } from "../design";
export const Hello = () => (
  <Paper background="bg-london.jpg" dark>
    <Headline>在情境中，学会英语</Headline>
    <div
      style={{
        position: "absolute",
        top: 295,
        left: 88,
        fontSize: 28,
        letterSpacing: 6,
        color: "#e4d6b8",
      }}
    >
      COOVINGO · 咕游记
    </div>
    <NativeScreen
      file="08-story.png"
      x={-80}
      y={730}
      width={440}
      angle={-8}
      delay={20}
    />
    <NativeScreen
      file="09-favorites.png"
      x={730}
      y={730}
      width={440}
      angle={8}
      delay={32}
    />
    <NativeScreen file="05-city.png" x={260} y={505} width={560} delay={8} />
  </Paper>
);
