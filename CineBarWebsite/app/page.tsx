import Home from "./home";
import { messages } from "./i18n";

export default function HomePage() {
  return <Home m={messages["zh-Hans"]} locale="zh-Hans" />;
}
