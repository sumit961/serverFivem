import { Text, SimpleGrid, Divider, CircularProgress, CircularProgressLabel} from "@chakra-ui/react";
import { Speed } from "../../interfaces/speed";
import { Locale } from "../../interfaces/locale";

interface Props {
  speed: Speed;
}

const SpeedList: React.FC<Props> = (props: Props) => {

  return (
    <SimpleGrid columns={1} spacing={0} padding='5px 10px 5px 10px'>
      <Text noOfLines={1} textAlign='center'>{Locale.ui_speed_label || 'Speed'}</Text>
      <Divider />
        <CircularProgress capIsRound={false} min={0} max={160} value={props.speed.velocity} size='100%' padding='50% 0 20% 0'>
          <CircularProgressLabel fontSize={15} padding='50% 0 20% 0'>{props.speed.velocity} {Locale.ui_speed_unit || 'MPH'}</CircularProgressLabel>
        </CircularProgress>
    </SimpleGrid>
  );
};

export default SpeedList;