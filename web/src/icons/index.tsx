/**
 * Icon barrel. Generic UI icons come from lucide-react (matches the
 * macOS app's preference for Lucide via SPM dep). Project-specific
 * icons that have no Lucide equivalent remain hand-drawn SVG.
 */
import type { LucideProps } from "lucide-react";
import {
  MessageSquare,
  Sidebar,
  Settings as LucideSettings,
  Pin,
  Archive,
  Send,
  Square,
  Mic,
  FolderOpen,
  FileText,
  Terminal,
  Search,
  Globe,
  Bot,
  Plus,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  ChevronUp,
  KeyRound,
  Database,
  Brain,
  Puzzle,
  Server,
} from "lucide-react";

const defaults = (size?: number): LucideProps => ({
  size: size ?? 16,
  strokeWidth: 1.6,
  absoluteStrokeWidth: false,
});

type IconArgs = { size?: number; className?: string };

const wrap = (Comp: typeof MessageSquare) =>
  ({ size, className }: IconArgs) => <Comp {...defaults(size)} className={className} />;

export const ChatIcon         = wrap(MessageSquare);
export const SidebarIcon      = wrap(Sidebar);
export const SettingsIcon     = wrap(LucideSettings);
export const PinIcon          = wrap(Pin);
export const ArchiveIcon      = wrap(Archive);
export const SendIcon         = wrap(Send);
export const StopIcon         = wrap(Square);
export const MicIcon          = wrap(Mic);
export const FolderOpenIcon   = wrap(FolderOpen);
export const FileChipIcon     = wrap(FileText);
export const TerminalIcon     = wrap(Terminal);
export const SearchIcon       = wrap(Search);
export const GlobeIcon        = wrap(Globe);
export const BotIcon          = wrap(Bot);
export const PlusIcon         = wrap(Plus);
export const ChevronLeftIcon  = wrap(ChevronLeft);
export const ChevronRightIcon = wrap(ChevronRight);
export const ChevronDownIcon  = wrap(ChevronDown);
export const ChevronUpIcon    = wrap(ChevronUp);
export const KeyIcon          = wrap(KeyRound);
export const DatabaseIcon     = wrap(Database);
export const BrainIcon        = wrap(Brain);
export const PuzzleIcon       = wrap(Puzzle);
export const ServerIcon       = wrap(Server);
