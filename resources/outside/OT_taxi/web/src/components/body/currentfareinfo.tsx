import { SimpleGrid, Divider, Stat, StatLabel, StatNumber, StatGroup, StatHelpText, Tooltip, IconButton, Flex, useToast, Center} from "@chakra-ui/react";
import { Currentfareinfo } from "../../interfaces/currentfareinfo";
import { FaSignOutAlt } from 'react-icons/fa';
import { fetchNui } from "../../utils/fetchNui";
import { Locale } from "../../interfaces/locale";

interface Props {
  currentfareinfo: Currentfareinfo;
}

interface ReturnData {
  success: boolean;
  reason: string;
}

const DocinfoList: React.FC<Props> = (props: Props) => {
  const toast = useToast()
  return (
    <SimpleGrid columns={1} spacing={0.5} >
      <StatGroup padding='0.2vh 0px 0.2vh 2.5vw'>
        <Stat>
          <StatLabel>{Locale.ui_current_fare || 'Current Fare'}</StatLabel>
          <StatNumber>{Locale.ui_currency || '$'}{props.currentfareinfo?.currentfare}</StatNumber>
        </Stat>
        <Stat>
          <StatLabel>{Locale.ui_base_fare || 'Base Fare'}</StatLabel>
          <StatNumber>{Locale.ui_currency || '$'}{props.currentfareinfo?.basefare}</StatNumber>
        </Stat>
        <Stat>
          <StatLabel>{Locale.ui_per_minute || 'Per Minute'}</StatLabel>
          <StatNumber>{Locale.ui_currency || '$'}{props.currentfareinfo?.perminute}</StatNumber>
        </Stat>
      </StatGroup>
      <Divider/>
        <Stat padding='0 0 0 0.5vw'>
          <StatLabel fontSize={14}>{Locale.ui_customer_name || 'Customer Name:'}</StatLabel>
          <StatHelpText fontSize={17}>{props.currentfareinfo?.customer}</StatHelpText>
        </Stat>
        <Divider/>
          <Stat padding='0 0 0 0.5vw'>
            <StatLabel fontSize={14}>{Locale.ui_customer_destination || 'Destination:'}</StatLabel>
            <Flex minWidth='max-content' align={'center'} gap='300' >
              <StatHelpText fontSize={17}>{props.currentfareinfo?.destination}</StatHelpText>
            </Flex>
          </Stat>
          <div>
            <Center>
              <Tooltip label={Locale.ui_cancel_tooltip || 'Cancel Job'}>  
                <IconButton aria-label='test' icon={<FaSignOutAlt />} size='xs' borderRadius={3} minWidth='95%' bgColor={'red.500'} onClick={() =>
                    fetchNui<ReturnData>('canceljob').then(retData => {}).catch(e => {
                    console.log('Setting mock data due to error', e)
                    toast({title: 'LS Taxi', description: "Error Occured", status: 'error', duration: 4000, isClosable: true, position: 'top'})
                  })}> </IconButton>
              </Tooltip>
            </Center>
          </div>
    </SimpleGrid>
  );
};

export default DocinfoList;