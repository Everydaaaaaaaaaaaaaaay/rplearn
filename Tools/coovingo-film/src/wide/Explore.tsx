import { Canvas, Copy, Phone } from "./design";
export const Explore = () => (
  <Canvas dark bg="bg-london.jpg">
    <Copy
      title={"打开世界地图，\n去下一座城市。"}
      body={"选择目的地，探索城市与当地生活。\n让新的地方，带来新的交流机会。"}
      width={850}
      top={210}
    />
    <Phone file="map-singapore.png" x={1090} y={75} w={425} angle={-2} />
    <Phone
      file="city-singapore.png"
      x={1510}
      y={190}
      w={320}
      angle={3}
      delay={26}
    />
  </Canvas>
);
